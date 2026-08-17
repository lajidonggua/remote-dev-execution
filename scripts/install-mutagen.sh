#!/bin/sh

set -u
umask 077

EX_USAGE=64
EX_UNAVAILABLE=69
DEFAULT_VERSION=${MUTAGEN_INSTALL_VERSION:-0.18.1}

usage() {
  cat <<'EOF'
Usage:
  install-mutagen.sh [--version VERSION] [--bin-dir DIR] [--force]

Install a pinned Mutagen release into a user-owned bin directory without sudo.
The default destination is ~/.local/bin and the release archive is verified
against the official SHA256SUMS manifest before installation.

Options:
  --version VERSION  Mutagen release version (default: 0.18.1).
  --bin-dir DIR      Absolute destination directory (default: ~/.local/bin).
  --force            Replace a different existing Mutagen executable.
  -h, --help         Show this help.
EOF
}

fail() {
  code=$1
  shift
  printf 'install-mutagen: %s\n' "$*" >&2
  exit "$code"
}

say() {
  printf 'install-mutagen: %s\n' "$*"
}

download() {
  source_url=$1
  destination=$2

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 20 -o "$destination" "$source_url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$destination" "$source_url"
  else
    fail "$EX_UNAVAILABLE" 'curl or wget is required to download Mutagen'
  fi
}

checksum() {
  checksum_file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$checksum_file" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$checksum_file" | awk '{ print $1 }'
  else
    fail "$EX_UNAVAILABLE" 'sha256sum or shasum is required to verify Mutagen'
  fi
}

cleanup() {
  if [ -n "${target_tmp:-}" ]; then
    rm -f "$target_tmp"
  fi
  if [ -n "${temp_dir:-}" ]; then
    rm -rf "$temp_dir"
  fi
}

[ -n "${HOME:-}" ] || fail "$EX_UNAVAILABLE" 'HOME is required'

version=$DEFAULT_VERSION
bin_dir=$HOME/.local/bin
force=0

while [ "$#" -gt 0 ]; do
  case $1 in
    --version)
      [ "$#" -ge 2 ] || fail "$EX_USAGE" '--version requires a value'
      version=$2
      shift 2
      ;;
    --bin-dir)
      [ "$#" -ge 2 ] || fail "$EX_USAGE" '--bin-dir requires a value'
      bin_dir=$2
      shift 2
      ;;
    --force)
      force=1
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

version=${version#v}
case $version in
  ''|*[!A-Za-z0-9._-]*) fail "$EX_USAGE" 'version contains unsupported characters' ;;
esac
case $bin_dir in
  /*) ;;
  *) fail "$EX_USAGE" '--bin-dir must be an absolute path' ;;
esac

case $(uname -s 2>/dev/null) in
  Darwin) release_os=darwin ;;
  Linux) release_os=linux ;;
  *) fail "$EX_UNAVAILABLE" 'automatic installation supports only macOS and Linux' ;;
esac

case $(uname -m 2>/dev/null) in
  x86_64|amd64) release_arch=amd64 ;;
  arm64|aarch64) release_arch=arm64 ;;
  *) fail "$EX_UNAVAILABLE" 'automatic installation supports only amd64 and arm64' ;;
esac

target=$bin_dir/mutagen
if [ -d "$target" ]; then
  fail "$EX_USAGE" "Mutagen destination is a directory: $target"
fi
if [ -x "$target" ] && [ "$force" -eq 0 ]; then
  installed_version=$("$target" version 2>/dev/null || true)
  if [ "$installed_version" = "$version" ]; then
    say "already installed: $target"
    exit 0
  fi
fi

if { [ -e "$target" ] || [ -L "$target" ]; } && [ "$force" -eq 0 ]; then
  fail "$EX_USAGE" "another file already exists at $target; use --force to replace it"
fi

archive=mutagen_${release_os}_${release_arch}_v${version}.tar.gz
release_base=${MUTAGEN_RELEASE_BASE_URL:-https://github.com/mutagen-io/mutagen/releases/download/v$version}
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/rde-mutagen-install.XXXXXX") ||
  fail "$EX_UNAVAILABLE" 'cannot create a temporary installation directory'
target_tmp=
trap 'cleanup' 0
trap 'exit 129' HUP INT TERM

archive_path=$temp_dir/$archive
sums_path=$temp_dir/SHA256SUMS
download "$release_base/$archive" "$archive_path" ||
  fail "$EX_UNAVAILABLE" 'cannot download the Mutagen release archive'
download "$release_base/SHA256SUMS" "$sums_path" ||
  fail "$EX_UNAVAILABLE" 'cannot download the Mutagen checksum manifest'

expected_checksum=$(awk -v archive="$archive" '
  $2 == archive || $2 == "*" archive { print $1; exit }
' "$sums_path")
case $expected_checksum in
  ''|*[!A-Fa-f0-9]*) fail "$EX_UNAVAILABLE" 'release checksum manifest does not contain the selected archive' ;;
esac
[ "${#expected_checksum}" -eq 64 ] ||
  fail "$EX_UNAVAILABLE" 'release checksum has an invalid length'

actual_checksum=$(checksum "$archive_path") ||
  fail "$EX_UNAVAILABLE" 'cannot compute the release archive checksum'
[ "$actual_checksum" = "$expected_checksum" ] ||
  fail "$EX_UNAVAILABLE" 'release archive checksum verification failed'

tar -xzf "$archive_path" -C "$temp_dir" mutagen ||
  fail "$EX_UNAVAILABLE" 'cannot extract the Mutagen executable'
[ -f "$temp_dir/mutagen" ] ||
  fail "$EX_UNAVAILABLE" 'release archive does not contain the Mutagen executable'

mkdir -p "$bin_dir" ||
  fail "$EX_UNAVAILABLE" "cannot create destination directory: $bin_dir"
target_tmp=$bin_dir/.mutagen.tmp.$$
if [ -e "$target_tmp" ] || [ -L "$target_tmp" ]; then
  fail "$EX_UNAVAILABLE" "temporary installation path is already occupied: $target_tmp"
fi
cp "$temp_dir/mutagen" "$target_tmp" ||
  fail "$EX_UNAVAILABLE" 'cannot stage the Mutagen executable'
chmod 0755 "$target_tmp" ||
  fail "$EX_UNAVAILABLE" 'cannot set Mutagen executable permissions'

if { [ -e "$target" ] || [ -L "$target" ]; } && [ "$force" -eq 0 ]; then
  fail "$EX_USAGE" "another file appeared at $target during installation"
fi
mv -f "$target_tmp" "$target" ||
  fail "$EX_UNAVAILABLE" "cannot install Mutagen at $target"
target_tmp=

say "installed Mutagen $version at $target"
case :${PATH:-}: in
  *:"$bin_dir":*) ;;
  *) say "add $bin_dir to PATH, or set DEV_EXEC_MUTAGEN_BIN=$target" ;;
esac
