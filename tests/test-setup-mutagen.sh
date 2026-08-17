#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
setup_mutagen=$script_dir/scripts/setup-mutagen.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rde-mutagen-setup-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fake_bin=$test_root/bin
fake_mutagen=$fake_bin/mutagen
fake_ssh=$fake_bin/ssh
mutagen_log=$test_root/mutagen.log
mutagen_state=$test_root/mutagen.state
ssh_marker=$test_root/ssh.called
mkdir -p "$fake_bin"

cat > "$fake_mutagen" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_MUTAGEN_LOG"
case " $* " in
  *' --template '*)
    printf '%s' "${FAKE_MUTAGEN_HEALTH:-ok}"
    exit "${FAKE_MUTAGEN_HEALTH_STATUS:-0}"
    ;;
esac
case ${1-}:${2-} in
  sync:list)
    [ -f "$FAKE_MUTAGEN_STATE" ] || exit "${FAKE_MUTAGEN_LIST_MISSING_STATUS:-1}"
    ;;
  sync:create)
    create_status=${FAKE_MUTAGEN_CREATE_STATUS:-0}
    [ "$create_status" -eq 0 ] && : > "$FAKE_MUTAGEN_STATE"
    exit "$create_status"
    ;;
  sync:flush)
    exit "${FAKE_MUTAGEN_FLUSH_STATUS:-0}"
    ;;
  sync:terminate)
    rm -f "$FAKE_MUTAGEN_STATE"
    ;;
esac
exit 0
EOF
chmod 0755 "$fake_mutagen"

cat > "$fake_ssh" <<'EOF'
#!/bin/sh
printf '%s\n' 'ssh-called' > "$FAKE_SSH_MARKER"
exit "${FAKE_SSH_STATUS:-0}"
EOF
chmod 0755 "$fake_ssh"

project=$test_root/project
nested=$project/packages/example
mkdir -p "$nested"
project=$(CDPATH= cd -P "$project" && pwd -P)
nested=$project/packages/example
git init -q "$project"
cat > "$project/.dev-exec.env" <<EOF
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_SHELL=/bin/sh
DEV_EXEC_MUTAGEN_BIN=$fake_mutagen
EOF

output=$test_root/output
error=$test_root/error
PATH="$fake_bin:$PATH" \
FAKE_MUTAGEN_LOG="$mutagen_log" \
FAKE_MUTAGEN_STATE="$mutagen_state" \
FAKE_SSH_MARKER="$ssh_marker" \
  sh -c "cd '$nested' && '$setup_mutagen' --name test-session --ignore node_modules" \
    > "$output" 2> "$error"

grep -Fqx "DEV_EXEC_MUTAGEN_SESSION='test-session'" "$project/.dev-exec.env"
grep -Fqx '.dev-exec.env' "$project/.git/info/exclude"
grep -Fq 'sync create --name test-session' "$mutagen_log"
grep -Fq -- '--mode two-way-safe' "$mutagen_log"
grep -Fq -- '--ignore-vcs' "$mutagen_log"
grep -Fq -- '--ignore .dev-exec.env' "$mutagen_log"
grep -Fq -- '--ignore node_modules' "$mutagen_log"
grep -Fq "$project" "$mutagen_log"
grep -Fq 'test-host:/authoritative/project' "$mutagen_log"
grep -Fqx 'setup-mutagen: Mutagen session created and project configuration updated' "$output"
grep -Fqx 'dev-exec doctor: synchronization tool: available' "$output"
grep -Fqx 'dev-exec doctor: synchronization session: available' "$output"
grep -Fqx 'dev-exec doctor: synchronization health: healthy' "$output"
grep -Fqx 'dev-exec doctor: synchronization preflight: passed' "$output"
grep -Fqx 'dev-exec doctor: authoritative execution: ready' "$output"
[ -f "$ssh_marker" ]
[ ! -s "$error" ]
! grep -Fq 'test-host' "$output"
! grep -Fq '/authoritative/project' "$output"
! grep -Fq "$project" "$output"

PATH="$fake_bin:$PATH" \
FAKE_MUTAGEN_LOG="$mutagen_log" \
FAKE_MUTAGEN_STATE="$mutagen_state" \
FAKE_SSH_MARKER="$ssh_marker" \
  sh -c "cd '$project' && '$setup_mutagen'" > "$output" 2> "$error"
[ "$(grep -c '^sync create ' "$mutagen_log")" -eq 1 ]
grep -Fqx 'setup-mutagen: Mutagen session is already configured; running integrated doctor' "$output"

status=0
if PATH="$fake_bin:$PATH" \
  FAKE_MUTAGEN_LOG="$mutagen_log" \
  FAKE_MUTAGEN_STATE="$mutagen_state" \
    sh -c "cd '$project' && '$setup_mutagen' --ignore build" > "$output" 2> "$error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 78 ]
grep -Fq 'cannot be applied after a Mutagen session is already configured' "$error"

for invalid_ignore in /absolute/path . .. ../outside path/../outside -not-a-path; do
  status=0
  if PATH="$fake_bin:$PATH" \
    FAKE_MUTAGEN_LOG="$mutagen_log" \
    FAKE_MUTAGEN_STATE="$mutagen_state" \
      sh -c "cd '$project' && '$setup_mutagen' --ignore '$invalid_ignore'" \
        > "$output" 2> "$error"; then
    status=0
  else
    status=$?
  fi
  [ "$status" -eq 64 ]
  grep -Fq 'ignore must be a relative project path' "$error"
done

failed_project=$test_root/failed-project
failed_state=$test_root/failed.state
failed_log=$test_root/failed.log
mkdir -p "$failed_project"
cat > "$failed_project/.dev-exec.env" <<EOF
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_MUTAGEN_BIN=$fake_mutagen
EOF
cp "$failed_project/.dev-exec.env" "$test_root/config.before"

status=0
if PATH="$fake_bin:$PATH" \
  FAKE_MUTAGEN_LOG="$failed_log" \
  FAKE_MUTAGEN_STATE="$failed_state" \
  FAKE_MUTAGEN_CREATE_STATUS=19 \
    sh -c "cd '$failed_project' && '$setup_mutagen' --name failed-session" \
      > "$output" 2> "$error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 19 ]
cmp -s "$test_root/config.before" "$failed_project/.dev-exec.env"
[ ! -e "$failed_state" ]
grep -Fq 'cannot create the Mutagen synchronization session' "$error"
! grep -Fq 'test-host' "$error"
! grep -Fq '/authoritative/project' "$error"

tracked_project=$test_root/tracked-project
tracked_state=$test_root/tracked.state
tracked_log=$test_root/tracked.log
mkdir -p "$tracked_project"
git init -q "$tracked_project"
cat > "$tracked_project/.dev-exec.env" <<EOF
DEV_EXEC_HOST=test-host
DEV_EXEC_DIR=/authoritative/project
DEV_EXEC_MUTAGEN_BIN=$fake_mutagen
EOF
git -C "$tracked_project" add .dev-exec.env

status=0
if PATH="$fake_bin:$PATH" \
  FAKE_MUTAGEN_LOG="$tracked_log" \
  FAKE_MUTAGEN_STATE="$tracked_state" \
    sh -c "cd '$tracked_project' && '$setup_mutagen' --name tracked-session" \
      > "$output" 2> "$error"; then
  status=0
else
  status=$?
fi
[ "$status" -eq 78 ]
grep -Fq '.dev-exec.env is tracked by Git' "$error"
[ ! -e "$tracked_state" ]
[ ! -e "$tracked_log" ]

printf '%s\n' 'test-setup-mutagen: all checks passed'
