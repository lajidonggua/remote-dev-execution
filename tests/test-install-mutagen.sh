#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
installer=$script_dir/scripts/install-mutagen.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rde-mutagen-installer-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

case $(uname -s) in
  Darwin) release_os=darwin ;;
  Linux) release_os=linux ;;
  *) printf '%s\n' 'test-install-mutagen: unsupported test operating system' >&2; exit 1 ;;
esac
case $(uname -m) in
  x86_64|amd64) release_arch=amd64 ;;
  arm64|aarch64) release_arch=arm64 ;;
  *) printf '%s\n' 'test-install-mutagen: unsupported test architecture' >&2; exit 1 ;;
esac

version=9.9.9
archive=mutagen_${release_os}_${release_arch}_v${version}.tar.gz
release_dir=$test_root/release
payload_dir=$test_root/payload
install_dir=$test_root/install/bin
mkdir -p "$release_dir" "$payload_dir"

cat > "$payload_dir/mutagen" <<'EOF'
#!/bin/sh
if [ "${1-}" = version ]; then
  printf '%s\n' '9.9.9'
  exit 0
fi
exit 0
EOF
chmod 0755 "$payload_dir/mutagen"
tar -czf "$release_dir/$archive" -C "$payload_dir" mutagen

if command -v sha256sum >/dev/null 2>&1; then
  archive_checksum=$(sha256sum "$release_dir/$archive" | awk '{ print $1 }')
else
  archive_checksum=$(shasum -a 256 "$release_dir/$archive" | awk '{ print $1 }')
fi
printf '%s  %s\n' "$archive_checksum" "$archive" > "$release_dir/SHA256SUMS"

MUTAGEN_RELEASE_BASE_URL=file://$release_dir \
  "$installer" --version "$version" --bin-dir "$install_dir" >/dev/null
[ -x "$install_dir/mutagen" ]
[ "$("$install_dir/mutagen" version)" = "$version" ]

MUTAGEN_RELEASE_BASE_URL=file://$release_dir \
  "$installer" --version "$version" --bin-dir "$install_dir" >/dev/null

directory_install=$test_root/directory-install/bin
mkdir -p "$directory_install/mutagen"
if MUTAGEN_RELEASE_BASE_URL=file://$release_dir \
  "$installer" --version "$version" --bin-dir "$directory_install" --force >/dev/null 2>&1; then
  printf '%s\n' 'install-mutagen unexpectedly treated a destination directory as an executable' >&2
  exit 1
fi
[ -d "$directory_install/mutagen" ]

bad_version=9.9.8
bad_archive=mutagen_${release_os}_${release_arch}_v${bad_version}.tar.gz
bad_release_dir=$test_root/bad-release
bad_install_dir=$test_root/bad-install/bin
mkdir -p "$bad_release_dir"
cp "$release_dir/$archive" "$bad_release_dir/$bad_archive"
printf '%064d  %s\n' 0 "$bad_archive" > "$bad_release_dir/SHA256SUMS"

if MUTAGEN_RELEASE_BASE_URL=file://$bad_release_dir \
  "$installer" --version "$bad_version" --bin-dir "$bad_install_dir" >/dev/null 2>&1; then
  printf '%s\n' 'install-mutagen unexpectedly accepted a checksum mismatch' >&2
  exit 1
fi
[ ! -e "$bad_install_dir/mutagen" ]

printf '%s\n' 'test-install-mutagen: all checks passed'
