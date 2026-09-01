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
if [ "${FAKE_MUTAGEN_REMOTE:-0}" = 1 ]; then
  remote_command=
  for argument do
    remote_command=$argument
  done
  case $remote_command in
    *mutagen*version*) exit 0 ;;
    *mutagen*sync*list*--template*) printf 'ok'; exit 0 ;;
    *mutagen*sync*list*) exit 0 ;;
    *mutagen*sync*flush*) exit 0 ;;
  esac
fi
if [ "${FAKE_SSH_EXEC:-0}" = 1 ]; then
  remote_command=
  for argument do
    remote_command=$argument
  done
  exec sh -c "$remote_command"
fi
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
printf '%s\n' "$*" >> "$FAKE_MUTAGEN_MARKER"
case " $* " in
  *' --template '*)
    printf '%s' "${FAKE_MUTAGEN_HEALTH:-ok}"
    exit "${FAKE_MUTAGEN_HEALTH_STATUS:-0}"
    ;;
esac
printf 'mutagen-private-stdout\n'
printf 'mutagen-private-stderr\n' >&2
case ${1-}:${2-} in
  sync:list) exit "${FAKE_MUTAGEN_LIST_STATUS:-${FAKE_MUTAGEN_STATUS:-0}}" ;;
  sync:flush) exit "${FAKE_MUTAGEN_FLUSH_STATUS:-${FAKE_MUTAGEN_STATUS:-0}}" ;;
esac
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
grep -Fq '<-T>' "$output"
grep -Fq '<-o><BatchMode=yes>' "$output"
grep -Fq '<-o><ClearAllForwardings=yes>' "$output"
grep -Fq '<-o><ForwardAgent=no>' "$output"
grep -Fq '<-o><ForwardX11=no>' "$output"
grep -Fq '<-o><RequestTTY=no>' "$output"
grep -Fq '<-o><StrictHostKeyChecking=yes>' "$output"
grep -Fq '<test-host>' "$output"
grep -Fq "cd '/authoritative/project'" "$output"
grep -Fq "'hello world'" "$output"
[ -f "$mutagen_marker" ]
grep -Fqx 'sync flush -- test-session' "$mutagen_marker"
grep -Fq 'sync list --template ' "$mutagen_marker"

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
grep -Fqx 'dev-exec doctor: synchronization tool: available' "$doctor_output"
grep -Fqx 'dev-exec doctor: synchronization session: available' "$doctor_output"
grep -Fqx 'dev-exec doctor: synchronization health: healthy' "$doctor_output"
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
  FAKE_MUTAGEN_LIST_STATUS=0 \
  FAKE_MUTAGEN_FLUSH_STATUS=17 \
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

rm -f "$ssh_marker"
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_MUTAGEN_MARKER="$mutagen_marker" \
  FAKE_MUTAGEN_LIST_STATUS=0 \
  FAKE_MUTAGEN_FLUSH_STATUS=0 \
  FAKE_MUTAGEN_HEALTH=conflicts \
    sh -c "cd '$project' && '$wrapper' -- true" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 65 ]
grep -Fqx 'dev-exec: synchronization health check failed: conflicts detected; remote command not started' "$doctor_error"
! grep -Fq 'test-host' "$doctor_error"
[ ! -f "$ssh_marker" ]

rm -f "$ssh_marker"
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_MUTAGEN_MARKER="$mutagen_marker" \
  FAKE_MUTAGEN_LIST_STATUS=0 \
  FAKE_MUTAGEN_FLUSH_STATUS=0 \
  FAKE_MUTAGEN_HEALTH=disconnected \
    sh -c "cd '$project' && '$wrapper' -- true" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 65 ]
grep -Fqx 'dev-exec: synchronization health check failed: endpoint disconnected; remote command not started' "$doctor_error"
! grep -Fq 'test-host' "$doctor_error"
[ ! -f "$ssh_marker" ]

rm -f "$ssh_marker"
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_MUTAGEN_MARKER="$mutagen_marker" \
  FAKE_MUTAGEN_LIST_STATUS=18 \
    sh -c "cd '$project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 18 ]
grep -Fqx 'dev-exec doctor: synchronization session: unavailable' "$doctor_error"
! grep -Fq 'mutagen-private' "$doctor_output"
! grep -Fq 'mutagen-private' "$doctor_error"
[ ! -f "$ssh_marker" ]

missing_tool_project=$test_root/missing-tool-project
mkdir -p "$missing_tool_project"
cat > "$missing_tool_project/.dev-exec.env" <<EOF
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_MUTAGEN_SESSION=test-session
DEV_EXEC_MUTAGEN_BIN=$test_root/missing-mutagen
EOF

rm -f "$ssh_marker"
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
    sh -c "cd '$missing_tool_project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 69 ]
grep -Fqx 'dev-exec doctor: synchronization tool: unavailable' "$doctor_error"
! grep -Fq "$test_root" "$doctor_output"
! grep -Fq "$test_root" "$doctor_error"
[ ! -f "$ssh_marker" ]

missing_tool_marker=$test_root/missing-tool-called
missing_tool_error=$test_root/missing-tool-error
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$missing_tool_marker" \
    sh -c "cd '$missing_tool_project' && '$wrapper' -- true" > "$doctor_output" 2> "$missing_tool_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 69 ]
grep -Fqx 'dev-exec: synchronization tool unavailable; remote command not started' "$missing_tool_error"
[ ! -f "$missing_tool_marker" ]

remote_project=$test_root/remote-mutagen-project
mkdir -p "$remote_project"
cat > "$remote_project/.dev-exec.env" <<'EOF'
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_SHELL=/bin/sh
DEV_EXEC_MUTAGEN_SESSION=remote-session
DEV_EXEC_MUTAGEN_HOST=mutagen-control
EOF

PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_MUTAGEN_REMOTE=1 \
FAKE_SSH_STATUS=0 \
  sh -c "cd '$remote_project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"

grep -Fqx 'dev-exec doctor: configuration: valid' "$doctor_output"
grep -Fqx 'dev-exec doctor: synchronization tool: available' "$doctor_output"
grep -Fqx 'dev-exec doctor: synchronization session: available' "$doctor_output"
grep -Fqx 'dev-exec doctor: synchronization health: healthy' "$doctor_output"
grep -Fqx 'dev-exec doctor: synchronization preflight: passed' "$doctor_output"
grep -Fqx 'dev-exec doctor: authoritative execution: ready' "$doctor_output"
[ ! -s "$doctor_error" ]

host_only_project=$test_root/host-only-project
mkdir -p "$host_only_project"
cat > "$host_only_project/.dev-exec.env" <<'EOF'
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_MUTAGEN_HOST=mutagen-control
EOF

rm -f "$ssh_marker"
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
    sh -c "cd '$host_only_project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 64 ]
grep -Fqx 'dev-exec: DEV_EXEC_MUTAGEN_HOST requires DEV_EXEC_MUTAGEN_SESSION' "$doctor_error"
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

newline_project=$test_root/newline-project
mkdir -p "$newline_project"
cat > "$newline_project/.dev-exec.env" <<'EOF'
DEV_EXEC_HOST='private-host
with-newline'
DEV_EXEC_DIR=/authoritative/project
EOF

status=0
if PATH="$fake_bin:$PATH" \
    sh -c "cd '$newline_project' && '$wrapper' doctor" > "$doctor_output" 2> "$doctor_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 64 ]
grep -Fqx 'dev-exec: DEV_EXEC_HOST must not contain a newline' "$doctor_error"
! grep -Fq 'private-host' "$doctor_error"

summary_authoritative=$test_root/summary-authoritative
summary_project=$test_root/summary-project
summary_logs=$test_root/summary-logs
mkdir -p "$summary_authoritative" "$summary_project"
cat > "$summary_project/.dev-exec.env" <<EOF
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=$summary_authoritative
DEV_EXEC_SHELL=/bin/sh
EOF

summary_output=$test_root/summary-output
summary_error=$test_root/summary-error
summary_command='i=1; while [ "$i" -le 300 ]; do printf "stdout-%03d\n" "$i"; printf "stderr-%03d\n" "$i" >&2; i=$((i + 1)); done'
PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_SSH_EXEC=1 \
DEV_EXEC_LOG_DIR="$summary_logs" \
SUMMARY_COMMAND="$summary_command" \
  sh -c "cd '$summary_project' && '$wrapper' summary \"\$SUMMARY_COMMAND\"" \
  > "$summary_output" 2> "$summary_error"

grep -Fq 'dev-exec result: run=run.' "$summary_output"
grep -Fq 'status=succeeded exit=0' "$summary_output"
grep -Fq 'stdout-300' "$summary_output"
! grep -Fq 'stdout-001' "$summary_output"
grep -Fq 'stderr-300' "$summary_error"
! grep -Fq 'stderr-001' "$summary_error"
summary_run_id=$(sed -n 's/^dev-exec result: run=\([^ ]*\).*/\1/p' "$summary_output")
[ -n "$summary_run_id" ]
grep -Fq 'stdout-001' "$summary_logs/$summary_run_id/stdout.log"
grep -Fq 'stdout-300' "$summary_logs/$summary_run_id/stdout.log"
grep -Fq 'stderr-001' "$summary_logs/$summary_run_id/stderr.log"
grep -Fqx 'exit_status: 0' "$summary_logs/$summary_run_id/meta"

logs_output=$test_root/logs-output
DEV_EXEC_LOG_DIR="$summary_logs" \
  "$wrapper" logs "$summary_run_id" --stdout --tail 2 --max-bytes 128 > "$logs_output"
grep -Fq 'stdout-300' "$logs_output"
grep -Fq 'stdout-299' "$logs_output"
! grep -Fq 'stdout-298' "$logs_output"

DEV_EXEC_LOG_DIR="$summary_logs" \
  "$wrapper" logs "$summary_run_id" --stderr --match 'stderr-150' --context 1 > "$logs_output"
grep -Fq 'stderr-149' "$logs_output"
grep -Fq 'stderr-150' "$logs_output"
grep -Fq 'stderr-151' "$logs_output"
! grep -Fq 'stderr-001' "$logs_output"

failure_command='printf "failure-stdout\n"; i=1; while [ "$i" -le 500 ]; do printf "failure-stderr-%03d\n" "$i" >&2; i=$((i + 1)); done; exit 7'
status=0
if PATH="$fake_bin:$PATH" \
  FAKE_SSH_MARKER="$ssh_marker" \
  FAKE_SSH_EXEC=1 \
  DEV_EXEC_LOG_DIR="$summary_logs" \
  FAILURE_COMMAND="$failure_command" \
    sh -c "cd '$summary_project' && '$wrapper' --output=summary \"\$FAILURE_COMMAND\"" \
    > "$summary_output" 2> "$summary_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 7 ]
grep -Fq 'status=failed exit=7' "$summary_output"
grep -Fq 'failure-stdout' "$summary_output"
grep -Fq 'failure-stderr-500' "$summary_error"
! grep -Fq 'failure-stderr-001' "$summary_error"
failure_run_id=$(sed -n 's/^dev-exec result: run=\([^ ]*\).*/\1/p' "$summary_output")
grep -Fqx 'exit_status: 7' "$summary_logs/$failure_run_id/meta"
grep -Fq 'failure-stderr-001' "$summary_logs/$failure_run_id/stderr.log"

long_line_command='awk "BEGIN { for (i = 0; i < 50000; i++) printf \"x\"; printf \"END\\n\" }"'
PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_SSH_EXEC=1 \
DEV_EXEC_LOG_DIR="$summary_logs" \
LONG_LINE_COMMAND="$long_line_command" \
  sh -c "cd '$summary_project' && '$wrapper' --summary \"\$LONG_LINE_COMMAND\"" \
  > "$summary_output" 2> "$summary_error"
summary_size=$(wc -c < "$summary_output" | tr -d '[:space:]')
[ "$summary_size" -lt 3000 ]
grep -Fq 'END' "$summary_output"
long_line_run_id=$(sed -n 's/^dev-exec result: run=\([^ ]*\).*/\1/p' "$summary_output")
long_line_size=$(wc -c < "$summary_logs/$long_line_run_id/stdout.log" | tr -d '[:space:]')
[ "$long_line_size" -gt 50000 ]

nul_command="printf 'before\\000after\\n'"
PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_SSH_EXEC=1 \
DEV_EXEC_LOG_DIR="$summary_logs" \
NUL_COMMAND="$nul_command" \
  sh -c "cd '$summary_project' && '$wrapper' summary \"\$NUL_COMMAND\"" \
  > "$summary_output" 2> "$summary_error"
grep -Fq 'before?after' "$summary_output"
nul_run_id=$(sed -n 's/^dev-exec result: run=\([^ ]*\).*/\1/p' "$summary_output")
raw_nul_count=$(LC_ALL=C tr -cd '\000' < "$summary_logs/$nul_run_id/stdout.log" | wc -c | tr -d '[:space:]')
[ "$raw_nul_count" -eq 1 ]
display_nul_count=$(LC_ALL=C tr -cd '\000' < "$summary_output" | wc -c | tr -d '[:space:]')
[ "$display_nul_count" -eq 0 ]

noisy_summary_project=$test_root/noisy-summary-project
mkdir -p "$noisy_summary_project"
cat > "$noisy_summary_project/.dev-exec.env" <<EOF
printf '%s\n' 'summary-private-config-output'
printf '%s\n' 'summary-private-config-error' >&2
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=$summary_authoritative
DEV_EXEC_SHELL=/bin/sh
EOF
PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_SSH_EXEC=1 \
DEV_EXEC_LOG_DIR="$summary_logs" \
  sh -c "cd '$noisy_summary_project' && '$wrapper' summary -- true" \
  > "$summary_output" 2> "$summary_error"
! grep -Fq 'summary-private-config' "$summary_output"
! grep -Fq 'summary-private-config' "$summary_error"

status=0
if DEV_EXEC_LOG_DIR="$summary_logs" \
    "$wrapper" logs '../outside' > "$logs_output" 2> "$summary_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 64 ]
grep -Fqx 'dev-exec: invalid dev-exec run ID' "$summary_error"

status=0
if DEV_EXEC_LOG_DIR="$summary_logs" \
    "$wrapper" logs "$summary_run_id" --max-bytes 16385 > "$logs_output" 2> "$summary_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 64 ]
grep -Fqx 'dev-exec: --max-bytes cannot exceed 16384 bytes' "$summary_error"

status=0
if DEV_EXEC_LOG_DIR="$summary_logs" \
    "$wrapper" logs "$summary_run_id" --tail 201 > "$logs_output" 2> "$summary_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 64 ]
grep -Fqx 'dev-exec: --tail cannot exceed 200 lines' "$summary_error"

malicious_run=$summary_logs/run.malicious
mkdir -p "$malicious_run"
printf '%s\n' 'run_id: run.malicious' > "$malicious_run/meta"
ln -s "$summary_logs/$summary_run_id/stdout.log" "$malicious_run/stdout.log"
printf '%s\n' 'safe' > "$malicious_run/stderr.log"
status=0
if DEV_EXEC_LOG_DIR="$summary_logs" \
    "$wrapper" logs run.malicious > "$logs_output" 2> "$summary_error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 64 ]
grep -Fqx 'dev-exec: refusing to read a symlinked dev-exec run file: stdout.log' "$summary_error"

PATH="$fake_bin:$PATH" \
FAKE_SSH_MARKER="$ssh_marker" \
FAKE_SSH_EXEC=1 \
  sh -c "cd '$summary_project' && '$wrapper' stream -- printf explicit-stream" \
  > "$summary_output" 2> "$summary_error"
grep -Fq 'explicit-stream' "$summary_output"
! grep -Fq 'dev-exec result:' "$summary_output"

printf '%s\n' 'test-dev-exec: all checks passed'
