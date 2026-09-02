#!/bin/sh

# Regression coverage for the portable stat probe.
#
# The incident: GNU stat's -f means "filesystem status", so `stat -f '%u' file`
# on GNU/Linux prints several lines of filesystem detail and exits 1. Chained as
# `stat -f ... || stat -c ...` inside one command substitution, the failed
# probe's stdout was captured together with the real uid, and the config
# validator concluded the file was owned by someone else and refused to run.

set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
stat_helper=$script_dir/scripts/portable-stat.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rde-portable-stat-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fake_bin=$test_root/bin
stat_log=$test_root/stat.log
mkdir -p "$fake_bin"

# A stat that behaves like whichever implementation FAKE_STAT_PLATFORM names.
# The `gnu` case reproduces the incident exactly: the BSD form writes multi-line
# output to stdout and then exits non-zero.
cat > "$fake_bin/stat" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_STAT_LOG"
case $FAKE_STAT_PLATFORM:$1:$2 in
  gnu:-f:%u|gnu:-f:%Lp)
    printf '%s\n' '  File: "example"' '    ID: e33663a6567f5704 Namelen: 255' 'Block size: 4096'
    exit 1
    ;;
  gnu:-c:%u) printf '%s\n' '501' ;;
  gnu:-c:%a) printf '%s\n' '600' ;;
  bsd:-c:*)
    printf '%s\n' 'stat: illegal option -- c'
    exit 1
    ;;
  bsd:-f:%u) printf '%s\n' '502' ;;
  bsd:-f:%Lp) printf '%s\n' '640' ;;
  # A probe that exits 0 but answers with something that is not a number.
  liar:-c:%u|liar:-c:%a)
    printf '%s\n' '  File: "example"' 'Blocks: Total: 25125852'
    ;;
  liar:-f:%u) printf '%s\n' '503' ;;
  liar:-f:%Lp) printf '%s\n' '600' ;;
  broken:*) exit 1 ;;
  *) exit 98 ;;
esac
EOF
chmod 0700 "$fake_bin/stat"

. "$stat_helper"

probe() {
  : > "$stat_log"
  PATH="$fake_bin:$PATH" FAKE_STAT_LOG="$stat_log" FAKE_STAT_PLATFORM=$1 \
    rde_stat "$2" "$test_root/example"
}

# 1. GNU stat success, and the GNU form is tried first.
owner=$(probe gnu owner)
[ "$owner" = 501 ] || { echo 'GNU owner probe did not return the uid'; exit 1; }
head -n 1 "$stat_log" | grep -q '^-c ' ||
  { echo 'the GNU form must be attempted first'; exit 1; }
[ "$(grep -c '^-f ' "$stat_log")" -eq 0 ] ||
  { echo 'the BSD form must not run once the GNU form succeeded'; exit 1; }

mode=$(probe gnu mode)
[ "$mode" = 600 ] || { echo 'GNU mode probe did not return the mode'; exit 1; }

# 2. BSD fallback: the GNU form fails, the BSD form answers.
owner=$(probe bsd owner)
[ "$owner" = 502 ] || { echo 'BSD fallback did not return the uid'; exit 1; }
[ "$(grep -c '^-c ' "$stat_log")" -ge 1 ] ||
  { echo 'the GNU form should have been attempted before falling back'; exit 1; }
[ "$(grep -c '^-f ' "$stat_log")" -ge 1 ] ||
  { echo 'the BSD form should have been attempted'; exit 1; }

mode=$(probe bsd mode)
[ "$mode" = 640 ] || { echo 'BSD fallback did not return the mode'; exit 1; }

# 3. The incident itself: a failing probe writes multi-line stdout, and none of
#    it may reach the accepted value.
owner=$(probe gnu owner)
case $owner in
  *File:* | *Namelen* | *'Block size'* | *"
"*)
    echo 'failed-probe output contaminated the result'
    exit 1
    ;;
esac
[ "$owner" = 501 ] || { echo 'contaminated owner value'; exit 1; }

mode=$(probe gnu mode)
case $mode in
  *File:* | *"
"*) echo 'failed-probe output contaminated the mode'; exit 1 ;;
esac
[ "$mode" = 600 ] || { echo 'contaminated mode value'; exit 1; }

# 4. A probe that exits zero with output that is not a number is rejected, and
#    the next implementation is tried instead of trusting it.
owner=$(probe liar owner)
[ "$owner" = 503 ] || { echo 'a non-numeric successful probe must be rejected'; exit 1; }
mode=$(probe liar mode)
[ "$mode" = 600 ] || { echo 'a non-octal successful probe must be rejected'; exit 1; }

# 5. Shape validation is real: mode digits are octal, owner digits decimal.
rde_stat_is octal 600 || { echo '600 must be accepted as octal'; exit 1; }
if rde_stat_is octal 680; then echo '680 is not octal and must be rejected'; exit 1; fi
if rde_stat_is octal ''; then echo 'empty is not octal'; exit 1; fi
rde_stat_is decimal 1005 || { echo '1005 must be accepted as decimal'; exit 1; }
if rde_stat_is decimal 10x5; then echo '10x5 is not decimal'; exit 1; fi
if rde_stat_is decimal '1005
600'; then echo 'multi-line values must be rejected'; exit 1; fi

# 6. Every probe failing is a failure, not a silent empty answer.
if probe broken owner >/dev/null 2>&1; then
  echo 'rde_stat must fail when no stat implementation works'
  exit 1
fi

# 7. An unknown field is rejected.
if PATH="$fake_bin:$PATH" FAKE_STAT_LOG="$stat_log" FAKE_STAT_PLATFORM=gnu \
  rde_stat nonsense "$test_root/example" >/dev/null 2>&1; then
  echo 'rde_stat must reject an unknown field'
  exit 1
fi

echo 'portable stat: ok'
