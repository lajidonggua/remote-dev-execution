#!/bin/sh

set -u
umask 077

EX_USAGE=64
EX_CONFIG=78
EX_UNAVAILABLE=69

DEFAULT_REPO=${REMOTE_DEV_EXECUTION_REPO:-https://github.com/lajidonggua/remote-dev-execution.git}
DEFAULT_REF=${REMOTE_DEV_EXECUTION_REF:-}
newline='
'

usage() {
  cat <<'EOF'
Usage:
  install-skill.sh [options]

Install the canonical checkout and link it into a user-level Skill directory.
The default client is Claude Code. Use --client both for Claude and Codex.

Options:
  --repo URL       Git repository URL or local clone source.
  --ref COMMIT     Full 40- or 64-hex commit ID to install (required).
  --root DIR       Canonical checkout (default: ~/code/remote-dev-execution).
  --target DIR     Skill link target for a single client.
  --client NAME    claude, codex, or both (default: claude).
  --no-update      Use an existing checkout without fetching or changing it.
  --dry-run        Show actions without cloning, updating, or linking.
  -h, --help       Show this help.

Existing user files and links to another location are never replaced.
EOF
}

fail() {
  code=$1
  shift
  printf 'install-skill: %s\n' "$*" >&2
  exit "$code"
}

say() {
  printf 'install-skill: %s\n' "$*"
}

require_value() {
  option=$1
  value=${2-}
  [ -n "$value" ] || fail "$EX_USAGE" "$option requires a value"
  case $value in
    *"$newline"*) fail "$EX_USAGE" "$option must not contain a newline" ;;
  esac
}

require_absolute_path() {
  path_name=$1
  path_value=$2
  case $path_value in
    /*) ;;
    *) fail "$EX_USAGE" "$path_name must be an absolute path" ;;
  esac
  case $path_value in
    *"$newline"*) fail "$EX_USAGE" "$path_name must not contain a newline" ;;
  esac
}

require_ref() {
  ref_value=$1
  require_value --ref "$ref_value"
  case $ref_value in
    -*) fail "$EX_USAGE" '--ref must not begin with a hyphen' ;;
  esac
}

require_immutable_ref() {
  immutable_ref=$1
  case $immutable_ref in
    *[!A-Fa-f0-9]*)
      fail "$EX_USAGE" '--ref must be a full 40- or 64-hex commit ID'
      ;;
  esac
  case ${#immutable_ref} in
    40|64) ;;
    *) fail "$EX_USAGE" '--ref must be a full 40- or 64-hex commit ID' ;;
  esac
}

repo_identity() {
  repo_value=$1
  case $repo_value in
    git@github.com:*) repo_value=github.com/${repo_value#git@github.com:} ;;
    https://github.com/*) repo_value=github.com/${repo_value#https://github.com/} ;;
    http://github.com/*) repo_value=github.com/${repo_value#http://github.com/} ;;
    ssh://git@github.com/*) repo_value=github.com/${repo_value#ssh://git@github.com/} ;;
  esac
  repo_value=${repo_value%/}
  repo_value=${repo_value%.git}
  printf '%s\n' "$repo_value"
}

git_command() {
  if [ -x "$git_bin" ]; then
    printf '%s\n' "$git_bin"
    return 0
  fi
  git_bin_resolved=$(command -v "$git_bin" 2>/dev/null || true)
  [ -n "$git_bin_resolved" ] ||
    fail "$EX_UNAVAILABLE" "Git executable not found: $git_bin"
  printf '%s\n' "$git_bin_resolved"
}

checkout_is_clean() {
  checkout_status=$("$git_cmd" -C "$root_dir" status --porcelain 2>/dev/null) ||
    fail "$EX_CONFIG" "cannot inspect checkout: $root_dir"
  [ -z "$checkout_status" ] ||
    fail "$EX_CONFIG" "checkout has local changes; commit or stash them before updating: $root_dir"
}

checkout_matches_ref() {
  checkout_commit=$("$git_cmd" -C "$root_dir" rev-parse HEAD 2>/dev/null) ||
    fail "$EX_CONFIG" "cannot resolve checkout commit: $root_dir"
  [ "$checkout_commit" = "$ref_name" ] ||
    fail "$EX_CONFIG" "checkout HEAD does not match --ref: $root_dir"
}

verify_checkout() {
  [ -d "$root_dir" ] ||
    fail "$EX_CONFIG" "canonical checkout is not a directory: $root_dir"
  [ ! -L "$root_dir" ] ||
    fail "$EX_CONFIG" "canonical checkout must not be a symlink: $root_dir"
  "$git_cmd" -C "$root_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    fail "$EX_CONFIG" "canonical path is not a Git checkout: $root_dir"
  [ -f "$root_dir/SKILL.md" ] ||
    fail "$EX_CONFIG" "checkout does not contain SKILL.md: $root_dir"
}

verify_origin() {
  [ "$no_update" -eq 1 ] && return 0
  origin_url=$("$git_cmd" -C "$root_dir" remote get-url origin 2>/dev/null || true)
  [ -n "$origin_url" ] ||
    fail "$EX_CONFIG" "checkout has no origin remote; use --no-update or add the expected origin: $root_dir"
  expected_identity=$(repo_identity "$repo_url")
  actual_identity=$(repo_identity "$origin_url")
  [ "$expected_identity" = "$actual_identity" ] ||
    fail "$EX_CONFIG" "checkout origin does not match --repo (expected $expected_identity, got $actual_identity)"
}

checkout_ref() {
  checkout_is_clean
  "$git_cmd" -C "$root_dir" fetch --prune --tags origin ||
    fail "$EX_UNAVAILABLE" "cannot fetch $repo_url"

  if "$git_cmd" -C "$root_dir" show-ref --verify --quiet "refs/remotes/origin/$ref_name"; then
    if "$git_cmd" -C "$root_dir" show-ref --verify --quiet "refs/heads/$ref_name"; then
      "$git_cmd" -C "$root_dir" checkout "$ref_name" >/dev/null ||
        fail "$EX_UNAVAILABLE" "cannot check out branch: $ref_name"
      "$git_cmd" -C "$root_dir" merge --ff-only "origin/$ref_name" >/dev/null ||
        fail "$EX_UNAVAILABLE" "branch cannot be fast-forwarded: $ref_name"
    else
      "$git_cmd" -C "$root_dir" checkout --track -b "$ref_name" "origin/$ref_name" >/dev/null ||
        fail "$EX_UNAVAILABLE" "cannot create local tracking branch: $ref_name"
    fi
  elif "$git_cmd" -C "$root_dir" rev-parse --verify --quiet "refs/tags/$ref_name^{commit}" >/dev/null; then
    "$git_cmd" -C "$root_dir" checkout --detach "refs/tags/$ref_name" >/dev/null ||
      fail "$EX_UNAVAILABLE" "cannot check out tag: $ref_name"
  elif "$git_cmd" -C "$root_dir" rev-parse --verify --quiet "$ref_name^{commit}" >/dev/null; then
    "$git_cmd" -C "$root_dir" checkout --detach "$ref_name" >/dev/null ||
      fail "$EX_UNAVAILABLE" "cannot check out Git ref: $ref_name"
  else
    fail "$EX_CONFIG" "Git ref not found after fetching: $ref_name"
  fi
}

target_matches_root() {
  target_name=$1
  [ -L "$target_name" ] || return 1
  [ -d "$root_dir" ] && [ ! -L "$root_dir" ] || return 1
  target_real=$(CDPATH= cd -P "$target_name" 2>/dev/null && pwd -P || true)
  root_real=$(CDPATH= cd -P "$root_dir" 2>/dev/null && pwd -P || true)
  [ -n "$target_real" ] && [ "$target_real" = "$root_real" ]
}

preflight_target() {
  target_name=$1
  target_matches_root "$target_name" && return 0
  if [ -L "$target_name" ]; then
    [ -e "$target_name" ] ||
      fail "$EX_CONFIG" "Skill target is a broken symlink: $target_name"
    fail "$EX_CONFIG" "Skill target already points somewhere else: $target_name"
  fi
  [ ! -e "$target_name" ] ||
    fail "$EX_CONFIG" "Skill target already exists; refusing to replace it: $target_name"
}

install_target() {
  target_name=$1
  if target_matches_root "$target_name"; then
    if [ "$dry_run" -eq 1 ]; then
      say "would keep existing Skill link $target_name -> $root_dir"
    else
      say "Skill link already points to canonical checkout: $target_name"
    fi
    return 0
  fi
  preflight_target "$target_name"
  if [ "$dry_run" -eq 1 ]; then
    say "would link $target_name -> $root_dir"
    return 0
  fi
  target_parent=$(dirname "$target_name")
  mkdir -p "$target_parent" ||
    fail "$EX_UNAVAILABLE" "cannot create Skill directory: $target_parent"
  ln -s "$root_dir" "$target_name" ||
    fail "$EX_UNAVAILABLE" "cannot create Skill link: $target_name"
  say "linked $target_name -> $root_dir"
}

preflight_targets() {
  case $client_name in
    claude)
      target_dir=${custom_target:-$HOME/.claude/skills/remote-dev-execution}
      preflight_target "$target_dir"
      ;;
    codex)
      target_dir=${custom_target:-$HOME/.agents/skills/remote-dev-execution}
      preflight_target "$target_dir"
      ;;
    both)
      preflight_target "$HOME/.claude/skills/remote-dev-execution"
      preflight_target "$HOME/.agents/skills/remote-dev-execution"
      ;;
  esac
}

repo_url=$DEFAULT_REPO
ref_name=$DEFAULT_REF
root_dir=${HOME:-}/code/remote-dev-execution
client_name=claude
custom_target=
no_update=0
dry_run=0
git_bin=${REMOTE_DEV_EXECUTION_GIT:-git}

[ -n "${HOME:-}" ] || fail "$EX_CONFIG" 'HOME is required'

while [ "$#" -gt 0 ]; do
  case $1 in
    --repo)
      require_value --repo "${2-}"
      repo_url=$2
      shift 2
      ;;
    --ref)
      require_ref "${2-}"
      ref_name=$2
      shift 2
      ;;
    --root)
      require_value --root "${2-}"
      root_dir=$2
      shift 2
      ;;
    --target)
      require_value --target "${2-}"
      custom_target=$2
      shift 2
      ;;
    --client)
      require_value --client "${2-}"
      client_name=$2
      shift 2
      ;;
    --no-update)
      no_update=1
      shift
      ;;
    --dry-run)
      dry_run=1
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

require_absolute_path CANONICAL_CHECKOUT "$root_dir"
require_ref "$ref_name"
require_immutable_ref "$ref_name"
if [ -n "$custom_target" ]; then
  require_absolute_path SKILL_TARGET "$custom_target"
fi
case $repo_url in
  ''|-*|*"$newline"*) fail "$EX_USAGE" '--repo must be a non-empty value that does not begin with a hyphen or contain a newline' ;;
esac
case $client_name in
  claude|codex) ;;
  both)
    [ -z "$custom_target" ] ||
      fail "$EX_USAGE" '--target cannot be combined with --client both'
    ;;
  *) fail "$EX_USAGE" '--client must be claude, codex, or both' ;;
esac

preflight_targets

git_cmd=$(git_command)

if [ -e "$root_dir" ] || [ -L "$root_dir" ]; then
  verify_checkout
  verify_origin
  if [ "$no_update" -eq 1 ]; then
    checkout_matches_ref
    say "using existing checkout without updating: $root_dir"
  elif [ "$dry_run" -eq 1 ]; then
    checkout_is_clean
    say "would fetch and check out $ref_name in $root_dir"
  else
    checkout_ref
    say "updated checkout to $ref_name: $root_dir"
  fi
else
  if [ "$dry_run" -eq 1 ]; then
    say "would clone $repo_url at $ref_name into $root_dir"
  else
    mkdir -p "$(dirname "$root_dir")" ||
      fail "$EX_UNAVAILABLE" "cannot create canonical checkout parent: $(dirname "$root_dir")"
    "$git_cmd" clone "$repo_url" "$root_dir" ||
      fail "$EX_UNAVAILABLE" "cannot clone repository: $repo_url"
    checkout_ref
    say "cloned checkout at $ref_name: $root_dir"
  fi
fi

if [ "$dry_run" -eq 0 ]; then
  verify_checkout
else
  [ -f "$root_dir/SKILL.md" ] || say "checkout will be validated after clone: $root_dir/SKILL.md"
fi

case $client_name in
  claude)
    target_dir=${custom_target:-$HOME/.claude/skills/remote-dev-execution}
    require_absolute_path SKILL_TARGET "$target_dir"
    install_target "$target_dir"
    ;;
  codex)
    target_dir=${custom_target:-$HOME/.agents/skills/remote-dev-execution}
    require_absolute_path SKILL_TARGET "$target_dir"
    install_target "$target_dir"
    ;;
  both)
    install_target "$HOME/.claude/skills/remote-dev-execution"
    install_target "$HOME/.agents/skills/remote-dev-execution"
    ;;
esac

say 'installation complete'
