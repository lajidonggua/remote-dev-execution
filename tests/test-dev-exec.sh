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
printf 'mutagen-private-stdout\n'
printf 'mutagen-private-stderr\n' >&2
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

doctor_output=$test_root/doctor-output
doctor_error=$test_root/doctor-error
PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_MUTAGEN_MARKER="$mutagen_marker" \
FAKE_MUTAGEN_STATUS=0 \
  sh -c "cd '$project' && '$wrapper' doctor > '$doctor_output' 2> '$doctor_error'"

grep -Fqx 'dev-exec doctor: configuration: valid' "$doctor_output"
grep -Fqx 'dev-exec doctor: synchronization preflight: passed' "$doctor_output"
grep -Fqx 'dev-exec doctor: authoritative execution: ready' "$doctor_output"
! grep -Fq 'test-host' "$doctor_output"
! grep -Fq '/authoritative/project' "$doctor_output"
! grep -Fq 'test-session' "$doctor_output"
[ ! -s "$doctor_error" ]

rm -f "$ssh_marker"
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_MUTAGEN_MARKER="$mutagen_marker" \
  FAKE_MUTAGEN_STATUS=0 \
  FAKE_SSH_STATUS=29 \
    sh -c "cd '$project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 29 ]
grep -Fqx 'dev-exec doctor: authoritative execution: failed' "$doctor_error"
! grep -Fq 'test-host' "$doctor_error"

rm -f "$ssh_marker"
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_MUTAGEN_MARKER="$mutagen_marker" \
  FAKE_MUTAGEN_STATUS=17 \
    sh -c "cd '$project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 17 ]
grep -Fqx 'dev-exec doctor: synchronization preflight: failed' "$doctor_error"
! grep -Fq 'mutagen-private' "$doctor_output"
! grep -Fq 'mutagen-private' "$doctor_error"
[ ! -f "$ssh_marker" ]

no_sync_project=$test_root/no-sync-project
mkdir -p "$no_sync_project"
cat > "$no_sync_project/.dev-exec.env" <<'EOF'
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_SHELL=/bin/sh
EOF

PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_SSH_STATUS=0 \
  sh -c "cd '$no_sync_project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"
grep -Fqx 'dev-exec doctor: source freshness: not verified (no synchronization preflight configured)' "$doctor_output"
grep -Fqx 'dev-exec doctor: authoritative execution: ready' "$doctor_output"

noisy_project=$test_root/noisy-project
mkdir -p "$noisy_project"
cat > "$noisy_project/.dev-exec.env" <<'EOF'
printf '%s\n' 'private-config-output'
printf '%s\n' 'private-config-error' >&2
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_SHELL=/bin/sh
EOF

PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_SSH_STATUS=0 \
  sh -c "cd '$noisy_project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"
! grep -Fq 'private-config' "$doctor_output"
! grep -Fq 'private-config' "$doctor_error"

invalid_project=$test_root/private-project
mkdir -p "$invalid_project"
cat > "$invalid_project/.dev-exec.env" <<'EOF'
DEV_EXEC_HOST='private-host
EOF

status=0
if PATH="$fake_bin:$PATH" \
    sh -c "cd '$invalid_project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 64 ]
grep -Fqx 'dev-exec doctor: configuration: invalid' "$doctor_error"
! grep -Fq "$invalid_project" "$doctor_error"
! grep -Fq 'private-host' "$doctor_error"

printf '%s\n' 'test-dev-exec: all checks passed'
