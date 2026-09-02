#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
stat_helper=$script_dir/scripts/portable-stat.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rde-portable-stat-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fake_bin=$test_root/bin
stat_log=$test_root/stat.log
mkdir -p "$fake_bin"

cat > "$fake_bin/stat" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_STAT_LOG"
case $FAKE_STAT_PLATFORM:$1:$2 in
  gnu:-f:%u|gnu:-f:%Lp)
    printf '%s\n' 'failed-bsd-probe-stdout'
    exit 1
    ;;
  gnu:-c:%u)
    printf '%s\n' '501'
    ;;
  gnu:-c:%a)
    printf '%s\n' '640'
    ;;
  bsd:-f:%u)
    printf '%s\n' '502'
    ;;
  bsd:-f:%Lp)
    printf '%s\n' '600'
    ;;
  bsd:-c:*)
    printf '%s\n' 'unexpected-gnu-fallback'
    exit 99
    ;;
  *)
    exit 98
    ;;
esac
EOF
chmod 0700 "$fake_bin/stat"

. "$stat_helper"

gnu_owner=$(PATH="$fake_bin:$PATH" FAKE_STAT_LOG="$stat_log" FAKE_STAT_PLATFORM=gnu \
  rde_stat owner "$test_root/example")
gnu_mode=$(PATH="$fake_bin:$PATH" FAKE_STAT_LOG="$stat_log" FAKE_STAT_PLATFORM=gnu \
  rde_stat mode "$test_root/example")
[ "$gnu_owner" = 501 ]
[ "$gnu_mode" = 640 ]
case $gnu_owner$gnu_mode in
  *failed-bsd-probe-stdout*) exit 1 ;;
esac
[ "$(grep -c '^-f ' "$stat_log")" -eq 2 ]
[ "$(grep -c '^-c ' "$stat_log")" -eq 2 ]

: > "$stat_log"
bsd_owner=$(PATH="$fake_bin:$PATH" FAKE_STAT_LOG="$stat_log" FAKE_STAT_PLATFORM=bsd \
  rde_stat owner "$test_root/example")
bsd_mode=$(PATH="$fake_bin:$PATH" FAKE_STAT_LOG="$stat_log" FAKE_STAT_PLATFORM=bsd \
  rde_stat mode "$test_root/example")
[ "$bsd_owner" = 502 ]
[ "$bsd_mode" = 600 ]
[ "$(grep -c '^-f ' "$stat_log")" -eq 2 ]
if grep -q '^-c ' "$stat_log"; then
  printf '%s\n' 'portable stat unexpectedly used GNU fallback after BSD success' >&2
  exit 1
fi

printf '%s\n' 'test-portable-stat: all checks passed'
