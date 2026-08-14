#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
wrapper=$script_dir/scripts/dev-exec
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rde-exec-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fake_bin=$test_root/bin
project=$test_root/project/nested
mkdir -p "$fake_bin" "$project"

cat > "$fake_bin/ssh" <<'EOF'
#!/bin/sh
printf 'ssh-called\n' > "$FAKE_SSH_MARKER"
printf 'ssh-argv:'
for argument do
  printf '<%s>' "$argument"
done
printf '\nremote-stdout\n'
printf 'remote-stderr\n' >&2
exit "${FAKE_SSH_STATUS:-0}"
EOF
chmod 0700 "$fake_bin/ssh"

cat > "$fake_bin/mutagen" <<'EOF'
#!/bin/sh
printf 'mutagen-called\n' > "$FAKE_MUTAGEN_MARKER"
exit "${FAKE_MUTAGEN_STATUS:-0}"
EOF
chmod 0700 "$fake_bin/mutagen"

cat > "$test_root/project/.dev-exec.env" <<EOF
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_SHELL=/bin/sh
DEV_EXEC_MUTAGEN_SESSION=test-session
DEV_EXEC_MUTAGEN_BIN=$fake_bin/mutagen
EOF

ssh_marker=$test_root/ssh-called
mutagen_marker=$test_root/mutagen-called
output=$test_root/output
error=$test_root/error

PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_MUTAGEN_MARKER="$mutagen_marker" \
FAKE_MUTAGEN_STATUS=0 \
  sh -c "cd '$project' && '$wrapper' -- printf '%s' 'hello world' > '$output' 2> '$error'"

grep -Fq 'remote-stdout' "$output"
grep -Fq 'remote-stderr' "$error"
grep -Fq 'ssh-called' "$ssh_marker"
grep -Fq '<test-host>' "$output"
grep -Fq "cd '/authoritative/project'" "$output"
grep -Fq "'hello world'" "$output"
[ -f "$mutagen_marker" ]

rm -f "$ssh_marker"
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_MUTAGEN_MARKER="$mutagen_marker" \
  FAKE_MUTAGEN_STATUS=17 \
    sh -c "cd '$project' && '$wrapper' -- true" >/dev/null 2>&1; then
  printf '%s\n' 'dev-exec unexpectedly ignored a failed Mutagen flush' >&2
  exit 1
fi
[ ! -f "$ssh_marker" ]

status=0
if FAKE_SSH_STATUS=23 \
  PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_MUTAGEN_MARKER="$mutagen_marker" \
  FAKE_MUTAGEN_STATUS=0 \
    sh -c "cd '$project' && '$wrapper' -- true" >/dev/null 2>&1; then
  status=0
else
  status=$?
fi
[ "$status" -eq 23 ]

printf '%s\n' 'test-dev-exec: all checks passed'
