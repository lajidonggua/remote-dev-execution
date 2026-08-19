#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
relay=$script_dir/scripts/dev-relay
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rde-relay-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

test_home=$test_root/home
fake_bin=$test_root/bin
fake_ssh=$fake_bin/ssh
ssh_args=$test_root/ssh-args
ssh_stdin=$test_root/ssh-stdin
relay_config=$test_root/relay.env
mkdir -p "$test_home" "$fake_bin"

help_output=$("$relay" --help)
printf '%s\n' "$help_output" | grep -Fq -- '--client NAME'
printf '%s\n' "$help_output" | grep -Fq -- '--mutagen SESSION'
printf '%s\n' "$help_output" | grep -Fq -- '--mutagen-host HOST'
printf '%s\n' "$help_output" | grep -Fq -- '--clear-mutagen'
printf '%s\n' "$help_output" | grep -Fq 'not install or create Mutagen'

# ClearAllForwardings=yes suppresses command-line -R options as well, leaving a
# healthy control connection with no reverse listener.
sed -n '/^run_tunnel()/,/^}/p' "$relay" |
  grep -Fq 'set -- "$@" -o ClearAllForwardings=no'

cat > "$fake_ssh" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_SSH_ARGS"
cat > "$FAKE_SSH_STDIN"
exit "${FAKE_SSH_STATUS:-0}"
EOF
chmod 0700 "$fake_ssh"

cat > "$relay_config" <<EOF
DEV_RELAY_VM_HOST=test-vm
DEV_RELAY_LOCAL_PORT=22022
DEV_RELAY_REMOTE_PORT=22022
DEV_RELAY_VM_ALIAS=rde-test-dev
DEV_RELAY_STATE_DIR=$test_home/.local/state/remote-dev-execution/relay
DEV_RELAY_RUNTIME_DIR=/tmp/rde-relay-test-$$
DEV_RELAY_SSH_BIN=$fake_ssh
DEV_RELAY_SSHD_BIN=/usr/bin/true
DEV_RELAY_SSH_KEYGEN_BIN=/usr/bin/true
EOF

HOME="$test_home" \
DEV_RELAY_CONFIG="$relay_config" \
FAKE_SSH_ARGS="$ssh_args" \
FAKE_SSH_STDIN="$ssh_stdin" \
  "$relay" install-skill \
    --client both \
    --repo https://example.invalid/remote-dev-execution.git \
    --ref v0.2.0 >/dev/null

grep -Fqx 'test-vm' "$ssh_args"
grep -Fq "sh -s -- --repo 'https://example.invalid/remote-dev-execution.git' --ref 'v0.2.0' --client 'both'" "$ssh_args"
grep -Fq 'Install the canonical checkout and link it into a user-level Skill directory.' "$ssh_stdin"

: > "$ssh_args"
if HOME="$test_home" \
  DEV_RELAY_CONFIG="$relay_config" \
  FAKE_SSH_ARGS="$ssh_args" \
  FAKE_SSH_STDIN="$ssh_stdin" \
    "$relay" install-skill --client invalid >/dev/null 2>&1; then
  printf '%s\n' 'dev-relay unexpectedly accepted an invalid Skill client' >&2
  exit 1
fi
[ ! -s "$ssh_args" ]

: > "$ssh_args"
if HOME="$test_home" \
  DEV_RELAY_CONFIG="$relay_config" \
  FAKE_SSH_ARGS="$ssh_args" \
  FAKE_SSH_STDIN="$ssh_stdin" \
    "$relay" setup test-vm --mutagen '' >/dev/null 2>&1; then
  printf '%s\n' 'dev-relay setup unexpectedly accepted an empty Mutagen session' >&2
  exit 1
fi
[ ! -s "$ssh_args" ]

: > "$ssh_args"
if HOME="$test_home" \
  DEV_RELAY_CONFIG="$relay_config" \
  FAKE_SSH_ARGS="$ssh_args" \
  FAKE_SSH_STDIN="$ssh_stdin" \
    "$relay" setup test-vm --clear-mutagen >/dev/null 2>&1; then
  printf '%s\n' 'dev-relay setup unexpectedly accepted --clear-mutagen without --project' >&2
  exit 1
fi
[ ! -s "$ssh_args" ]

: > "$ssh_args"
if HOME="$test_home" \
  DEV_RELAY_CONFIG="$relay_config" \
  FAKE_SSH_ARGS="$ssh_args" \
  FAKE_SSH_STDIN="$ssh_stdin" \
    "$relay" setup test-vm --client invalid >/dev/null 2>&1; then
  printf '%s\n' 'dev-relay setup unexpectedly accepted an invalid Skill client' >&2
  exit 1
fi
[ ! -s "$ssh_args" ]

: > "$ssh_args"
if HOME="$test_home" \
  DEV_RELAY_CONFIG="$relay_config" \
  FAKE_SSH_ARGS="$ssh_args" \
  FAKE_SSH_STDIN="$ssh_stdin" \
    "$relay" setup test-vm \
      --project /project/on/vm /project/on/authoritative-environment \
      --mutagen -invalid >/dev/null 2>&1; then
  printf '%s\n' 'dev-relay setup unexpectedly accepted an option-like Mutagen session' >&2
  exit 1
fi
[ ! -s "$ssh_args" ]

: > "$ssh_args"
if HOME="$test_home" \
  DEV_RELAY_CONFIG="$relay_config" \
  FAKE_SSH_ARGS="$ssh_args" \
  FAKE_SSH_STDIN="$ssh_stdin" \
    "$relay" setup test-vm \
      --project /project/on/vm /project/on/authoritative-environment \
      --mutagen project-sync \
      --mutagen-host -invalid >/dev/null 2>&1; then
  printf '%s\n' 'dev-relay setup unexpectedly accepted an option-like Mutagen control host' >&2
  exit 1
fi
[ ! -s "$ssh_args" ]

printf '%s\n' 'test-dev-relay: all checks passed'
