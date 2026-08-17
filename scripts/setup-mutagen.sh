#!/bin/sh

set -u
umask 077

EX_USAGE=64
EX_UNAVAILABLE=69
EX_CONFIG=78
newline='
'

usage() {
  cat <<'EOF'
Usage:
  setup-mutagen.sh [--install] [--version VERSION] [--name SESSION]
                   [--ignore PATH]... [--verbose]

Find the nearest .dev-exec.env, use its directory as the editing endpoint,
and use DEV_EXEC_HOST plus DEV_EXEC_DIR as the authoritative endpoint. Create
a two-way-safe Mutagen session, add its name to the project configuration, and
run dev-exec doctor. Existing Mutagen assignments are never rewritten.

Options:
  --install          Install pinned Mutagen into ~/.local/bin when unavailable.
  --version VERSION  Version passed to install-mutagen.sh (default: 0.18.1).
  --name SESSION     Session name; otherwise derive a stable project-local name.
  --ignore PATH      Additional project-relative ignore; may be repeated.
  --verbose          Show underlying Mutagen setup output.
  -h, --help         Show this help.

VCS metadata and .dev-exec.env are always ignored. Add project-specific
dependency and build directories with --ignore rather than syncing them.
EOF
}

fail() {
  code=$1
  shift
  printf 'setup-mutagen: %s\n' "$*" >&2
  exit "$code"
}

say() {
  printf 'setup-mutagen: %s\n' "$*"
}

find_config() {
  search_dir=$(pwd -P 2>/dev/null) || return 1
  while :; do
    candidate=$search_dir/.dev-exec.env
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    [ "$search_dir" = / ] && return 1
    search_dir=${search_dir%/*}
    [ -n "$search_dir" ] || search_dir=/
  done
}

shell_quote() {
  escaped=$(printf '%s_' "$1" | sed "s/'/'\\\\''/g") || return 1
  escaped=${escaped%_}
  printf "'%s'" "$escaped"
}

has_assignment() {
  assignment_name=$1
  grep -Eq "^[[:space:]]*(export[[:space:]]+)?${assignment_name}=" "$config_file"
}

ensure_project_config_ignored() {
  command -v git >/dev/null 2>&1 || return 0
  repository_root=$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$repository_root" ] || return 0
  case $config_file in
    "$repository_root"/*) config_relative=${config_file#"$repository_root"/} ;;
    *) return 0 ;;
  esac

  if git -C "$repository_root" ls-files --error-unmatch -- "$config_relative" >/dev/null 2>&1; then
    fail "$EX_CONFIG" '.dev-exec.env is tracked by Git; remove it from the index before configuring Mutagen'
  fi

  git_dir=$(git -C "$repository_root" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$git_dir" ] || return 0
  case $git_dir in
    /*) ;;
    *) git_dir=$repository_root/$git_dir ;;
  esac
  exclude_file=$git_dir/info/exclude
  [ ! -L "$exclude_file" ] ||
    fail "$EX_CONFIG" 'Git local exclude is a symlink; refusing to update it'
  mkdir -p "${exclude_file%/*}" ||
    fail "$EX_UNAVAILABLE" 'cannot create the Git local exclude directory'
  touch "$exclude_file" ||
    fail "$EX_UNAVAILABLE" 'cannot update the Git local exclude file'
  if ! grep -Fqx "$config_relative" "$exclude_file" 2>/dev/null; then
    printf '\n# remote-dev-execution\n%s\n' "$config_relative" >> "$exclude_file" ||
      fail "$EX_UNAVAILABLE" 'cannot add .dev-exec.env to the Git local exclude file'
  fi
}

resolve_mutagen() {
  mutagen_candidate=${DEV_EXEC_MUTAGEN_BIN:-mutagen}
  mutagen_resolved=$(command -v "$mutagen_candidate" 2>/dev/null || true)
  if [ -n "$mutagen_resolved" ]; then
    printf '%s\n' "$mutagen_resolved"
    return 0
  fi

  if [ "$install_requested" -eq 1 ]; then
    installer=$script_dir/install-mutagen.sh
    [ -x "$installer" ] ||
      fail "$EX_UNAVAILABLE" 'bundled install-mutagen.sh is unavailable or not executable'
    if [ "$verbose" -eq 1 ]; then
      "$installer" --version "$install_version" >&2 || return $?
    else
      "$installer" --version "$install_version" >/dev/null 2>&1 || return $?
    fi
    mutagen_resolved=$(command -v "$mutagen_candidate" 2>/dev/null || true)
    if [ -n "$mutagen_resolved" ]; then
      printf '%s\n' "$mutagen_resolved"
      return 0
    fi
    fallback=$HOME/.local/bin/mutagen
    if [ "$bin_assignment_present" -eq 0 ] && [ -x "$fallback" ]; then
      printf '%s\n' "$fallback"
      return 0
    fi
  fi

  return 1
}

cleanup() {
  if [ -n "${config_tmp:-}" ]; then
    rm -f "$config_tmp"
  fi
}

[ -n "${HOME:-}" ] || fail "$EX_CONFIG" 'HOME is required'
script_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd) ||
  fail "$EX_UNAVAILABLE" 'cannot locate the bundled scripts directory'

install_requested=0
install_version=${MUTAGEN_INSTALL_VERSION:-0.18.1}
requested_session=
ignore_values=
verbose=0

while [ "$#" -gt 0 ]; do
  case $1 in
    --install)
      install_requested=1
      shift
      ;;
    --version)
      [ "$#" -ge 2 ] || fail "$EX_USAGE" '--version requires a value'
      install_version=$2
      shift 2
      ;;
    --name)
      [ "$#" -ge 2 ] || fail "$EX_USAGE" '--name requires a value'
      requested_session=$2
      shift 2
      ;;
    --ignore)
      [ "$#" -ge 2 ] || fail "$EX_USAGE" '--ignore requires a value'
      case $2 in
        ''|/*|.|./|..|../*|*/..|*/../*|-*|*"$newline"*)
          fail "$EX_USAGE" '--ignore must be a relative project path without dot-parent components or a newline' ;;
      esac
      if [ -n "$ignore_values" ]; then
        ignore_values=$ignore_values$newline$2
      else
        ignore_values=$2
      fi
      shift 2
      ;;
    --verbose)
      verbose=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "$EX_USAGE" "unknown option: $1"
      ;;
  esac
done

case $install_version in
  v*) install_version=${install_version#v} ;;
esac
case $install_version in
  ''|*[!A-Za-z0-9._-]*) fail "$EX_USAGE" 'version contains unsupported characters' ;;
esac
case $requested_session in
  '' ) ;;
  -*|*[!A-Za-z0-9._-]*) fail "$EX_USAGE" 'session name may contain only letters, digits, dots, underscores, and hyphens, and must not begin with a hyphen' ;;
esac

config_file=$(find_config) ||
  fail "$EX_CONFIG" 'no .dev-exec.env found in the current directory or its parents'
[ ! -L "$config_file" ] ||
  fail "$EX_CONFIG" 'refusing to update a symlinked .dev-exec.env'
[ -f "$config_file" ] ||
  fail "$EX_CONFIG" '.dev-exec.env is not a regular file'
sh -n "$config_file" >/dev/null 2>&1 ||
  fail "$EX_CONFIG" '.dev-exec.env is not valid POSIX shell syntax'
project_root=${config_file%/*}
[ -n "$project_root" ] || project_root=/
ensure_project_config_ignored

session_assignment_present=0
bin_assignment_present=0
has_assignment DEV_EXEC_MUTAGEN_SESSION && session_assignment_present=1
has_assignment DEV_EXEC_MUTAGEN_BIN && bin_assignment_present=1

unset DEV_EXEC_HOST DEV_EXEC_DIR DEV_EXEC_MUTAGEN_SESSION DEV_EXEC_MUTAGEN_BIN 2>/dev/null || true
# The project config is trusted shell syntax; see references/configuration.md.
# shellcheck disable=SC1090
. "$config_file" >/dev/null 2>&1
config_status=$?
[ "$config_status" -eq 0 ] || fail "$EX_CONFIG" 'cannot load .dev-exec.env'

[ -n "${DEV_EXEC_HOST:-}" ] || fail "$EX_CONFIG" 'DEV_EXEC_HOST is required in .dev-exec.env'
[ -n "${DEV_EXEC_DIR:-}" ] || fail "$EX_CONFIG" 'DEV_EXEC_DIR is required in .dev-exec.env'
case $DEV_EXEC_HOST in
  -*) fail "$EX_CONFIG" 'DEV_EXEC_HOST must not begin with a hyphen' ;;
esac
case $DEV_EXEC_DIR in
  /*) ;;
  *) fail "$EX_CONFIG" 'DEV_EXEC_DIR must be absolute in the authoritative environment' ;;
esac

mutagen_bin=$(resolve_mutagen) ||
  fail "$EX_UNAVAILABLE" 'Mutagen is unavailable; rerun with --install, or fix DEV_EXEC_MUTAGEN_BIN if it is explicitly configured'

need_bin_assignment=0
if [ "$bin_assignment_present" -eq 0 ]; then
  configured_command=${DEV_EXEC_MUTAGEN_BIN:-mutagen}
  configured_resolved=$(command -v "$configured_command" 2>/dev/null || true)
  if [ -z "$configured_resolved" ] || [ "$configured_resolved" != "$mutagen_bin" ]; then
    need_bin_assignment=1
  fi
fi

if [ -n "${DEV_EXEC_MUTAGEN_SESSION:-}" ]; then
  [ -z "$ignore_values" ] ||
    fail "$EX_CONFIG" '--ignore cannot be applied after a Mutagen session is already configured; update the session explicitly'
  if [ -n "$requested_session" ] && [ "$requested_session" != "$DEV_EXEC_MUTAGEN_SESSION" ]; then
    fail "$EX_CONFIG" 'the requested session differs from the session already configured'
  fi
  if [ "$need_bin_assignment" -eq 1 ]; then
    quoted_bin=$(shell_quote "$mutagen_bin") ||
      fail "$EX_UNAVAILABLE" 'cannot quote the Mutagen executable path'
    config_tmp=$config_file.tmp.$$
    [ ! -e "$config_tmp" ] && [ ! -L "$config_tmp" ] ||
      fail "$EX_CONFIG" 'temporary project configuration path already exists'
    trap 'cleanup' 0
    trap 'exit 129' HUP INT TERM
    cp "$config_file" "$config_tmp" ||
      fail "$EX_UNAVAILABLE" 'cannot stage the project configuration update'
    {
      printf '\n# Added by remote-dev-execution setup-mutagen\n'
      printf 'DEV_EXEC_MUTAGEN_BIN=%s\n' "$quoted_bin"
    } >> "$config_tmp" ||
      fail "$EX_UNAVAILABLE" 'cannot stage the Mutagen executable setting'
    chmod 0600 "$config_tmp" ||
      fail "$EX_UNAVAILABLE" 'cannot secure the staged project configuration'
    mv "$config_tmp" "$config_file" ||
      fail "$EX_UNAVAILABLE" 'cannot install the updated project configuration'
    config_tmp=
  fi
  say 'Mutagen session is already configured; running integrated doctor'
  exec "$script_dir/dev-exec" doctor
fi

if [ "$session_assignment_present" -eq 1 ]; then
  fail "$EX_CONFIG" 'DEV_EXEC_MUTAGEN_SESSION is already assigned but empty; remove or set that assignment explicitly'
fi

if [ -n "$requested_session" ]; then
  session=$requested_session
else
  project_name=${project_root##*/}
  project_name=$(printf '%s' "$project_name" | tr -c 'A-Za-z0-9._-' '-')
  project_name=$(printf '%.32s' "$project_name")
  [ -n "$project_name" ] || project_name=project
  fingerprint=$(printf '%s' "$config_file" | cksum | awk '{ print $1 }') ||
    fail "$EX_UNAVAILABLE" 'cannot derive a stable session name'
  session=rde-$project_name-$fingerprint
fi

if "$mutagen_bin" sync list -- "$session" >/dev/null 2>&1; then
  fail "$EX_CONFIG" 'a Mutagen session with the selected name already exists; configure it explicitly or choose another --name'
fi

quoted_session=$(shell_quote "$session") ||
  fail "$EX_UNAVAILABLE" 'cannot quote the Mutagen session name'
if [ "$need_bin_assignment" -eq 1 ]; then
  quoted_bin=$(shell_quote "$mutagen_bin") ||
    fail "$EX_UNAVAILABLE" 'cannot quote the Mutagen executable path'
fi

config_tmp=$config_file.tmp.$$
[ ! -e "$config_tmp" ] && [ ! -L "$config_tmp" ] ||
  fail "$EX_CONFIG" 'temporary project configuration path already exists'
trap 'cleanup' 0
trap 'exit 129' HUP INT TERM
cp "$config_file" "$config_tmp" ||
  fail "$EX_UNAVAILABLE" 'cannot stage the project configuration update'
{
  printf '\n# Added by remote-dev-execution setup-mutagen\n'
  printf 'DEV_EXEC_MUTAGEN_SESSION=%s\n' "$quoted_session"
  if [ "$need_bin_assignment" -eq 1 ]; then
    printf 'DEV_EXEC_MUTAGEN_BIN=%s\n' "$quoted_bin"
  fi
} >> "$config_tmp" ||
  fail "$EX_UNAVAILABLE" 'cannot stage Mutagen project settings'
chmod 0600 "$config_tmp" ||
  fail "$EX_UNAVAILABLE" 'cannot secure the staged project configuration'

set -- sync create \
  --name "$session" \
  --label remote-dev-execution=true \
  --mode two-way-safe \
  --ignore-vcs \
  --ignore .dev-exec.env
if [ -n "$ignore_values" ]; then
  old_ifs=$IFS
  IFS=$newline
  set -f
  for ignore_value in $ignore_values; do
    set -- "$@" --ignore "$ignore_value"
  done
  IFS=$old_ifs
fi
remote_endpoint=$DEV_EXEC_HOST:$DEV_EXEC_DIR
set -- "$@" "$project_root" "$remote_endpoint"

if [ "$verbose" -eq 1 ]; then
  "$mutagen_bin" "$@"
else
  "$mutagen_bin" "$@" >/dev/null 2>&1
fi
create_status=$?
if [ "$create_status" -ne 0 ]; then
  fail "$create_status" 'cannot create the Mutagen synchronization session; rerun with --verbose to inspect the underlying error'
fi

if [ "$verbose" -eq 1 ]; then
  "$mutagen_bin" sync flush -- "$session"
else
  "$mutagen_bin" sync flush -- "$session" >/dev/null 2>&1
fi
flush_status=$?
if [ "$flush_status" -ne 0 ]; then
  "$mutagen_bin" sync terminate -- "$session" >/dev/null 2>&1 || true
  fail "$flush_status" 'initial Mutagen flush failed; the new session was removed'
fi

if ! mv "$config_tmp" "$config_file"; then
  "$mutagen_bin" sync terminate -- "$session" >/dev/null 2>&1 || true
  fail "$EX_UNAVAILABLE" 'cannot install the updated project configuration; the new session was removed'
fi
config_tmp=

say 'Mutagen session created and project configuration updated'
say 'running integrated doctor'
exec "$script_dir/dev-exec" doctor
