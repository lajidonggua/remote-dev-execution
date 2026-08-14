# remote-dev-execution

An Agent Skill for a split development workflow:

```text
AI editing environment (VM, container, or secondary workspace)
        |
        | inspect and edit source locally
        v
dev-exec / SSH / optional Mutagen sync
        |
        v
Authoritative development environment (Mac, workstation, or build host)
        |
        | real toolchain, dependencies, services, containers, and runtime
        v
authoritative build, test, debug, and runtime result
```

The Skill keeps lightweight source work in the AI environment and routes
environment-dependent commands to the machine whose result is authoritative.
It supports direct SSH and a non-admin macOS reverse relay for the case where a
VM cannot connect inbound to the Mac.

**中文文档:** [README.zh-CN.md](README.zh-CN.md)

## What This Repository Contains

- `SKILL.md`: instructions loaded by Codex or Claude when the Skill is active.
- `scripts/dev-exec`: project-aware command wrapper with config lookup,
  optional Mutagen flush, SSH execution, and exit-status preservation.
- `scripts/dev-relay`: user-owned macOS `sshd` plus a Mac-initiated reverse
  SSH tunnel. It does not require administrator privileges.
- `scripts/install-skill.sh`: safe canonical-checkout and user-level-link
  installer for Claude Code or Codex.
- `references/configuration.md`: `.dev-exec.env` behavior and source-freshness
  rules.
- `references/reverse-relay.md`: relay security model, manual setup, and
  troubleshooting details.
- `assets/*.example`: templates containing placeholders only.

The repository is the canonical copy. Do not put project paths, SSH hosts,
usernames, IP addresses, private keys, passwords, tokens, or other secrets in
this repository.

## Choose Your Topology

| Situation | Recommended path | Is Mutagen required? |
| --- | --- | --- |
| The VM can SSH directly to the authoritative machine and both use one shared checkout | Direct SSH + `.dev-exec.env` | No |
| The VM and authoritative machine have separate checkouts | Direct SSH + a verified sync mechanism | Usually yes; Mutagen is optional if another sync is trusted |
| The authoritative machine is a Mac and the VM cannot connect inbound to it | `dev-relay setup` reverse relay | Only when the checkouts are separate |
| You need an interactive shell or terminal debugger | Relay/direct `ssh -t` | No, but source freshness still matters |

Mutagen is a synchronization tool, not an SSH replacement. This Skill uses it
only as a preflight: `dev-exec` runs `mutagen sync flush` and refuses to start
SSH if the flush fails. The wrapper does not decide which side wins a sync
conflict and does not silently copy generated changes back.

## Requirements

### On the AI environment / VM

- A POSIX shell (`sh`, Bash, Zsh, Dash, or Ksh).
- Git when installing or updating the Skill.
- An SSH client and a working SSH alias for the authoritative environment.
- A project checkout containing a local `.dev-exec.env`, or the required
  `DEV_EXEC_*` values exported in the process environment.

### On the authoritative environment

- The real project checkout and its toolchain, dependencies, services, Docker,
  SDKs, and runtime.
- An SSH server reachable through the configured alias, unless the reverse
  relay is used.
- Mutagen only when separate checkouts need Mutagen synchronization.

### Additional reverse-relay requirements

- macOS has `/usr/sbin/sshd`, `/usr/bin/ssh`, and `/usr/bin/ssh-keygen`.
- The Mac can already make a non-interactive SSH connection to the VM.
- The VM SSH server permits remote forwarding and has a POSIX-compatible login
  shell.
- The relay's high loopback ports are unused.

The reverse relay does not enable macOS Remote Login, bind port 22, change the
firewall, bind a public interface, or require `sudo`.

## Install the Skill

Install the Skill in the environment where the agent runs. If Claude Code runs
inside a VM, a link under the Mac's `~/.claude/skills` is invisible to it; the
VM needs its own checkout and link.

### Public repository

Run these commands in the VM (or other agent environment). The first command
creates the canonical checkout; the installer then creates the Claude link.

```sh
git clone https://github.com/lajidonggua/remote-dev-execution.git \
  ~/code/remote-dev-execution

~/code/remote-dev-execution/scripts/install-skill.sh \
  --repo https://github.com/lajidonggua/remote-dev-execution.git \
  --ref main \
  --client claude
```

Install both supported clients in the same user environment with:

```sh
~/code/remote-dev-execution/scripts/install-skill.sh --client both
```

The default targets are `~/.claude/skills/remote-dev-execution` for Claude Code
and `~/.agents/skills/remote-dev-execution` for Codex. Both are symlinks to the
same canonical checkout.

The installer is idempotent and conservative:

- It updates only a clean Git checkout whose `origin` matches `--repo`.
- It can use a branch, tag, or commit (`--ref`).
- It refuses an existing directory, broken link, or link to another location.
- It never uses `sudo` and never overwrites unrelated user files.
- `--no-update` uses an existing checkout without fetching.
- `--dry-run` previews the link actions.
- `--root DIR` selects another canonical checkout; `--target DIR` selects a
  custom target for one client.

Start a new Claude Code/Codex session after installing or updating the link so
the agent reloads Skill metadata and instructions.

### Internal team rollout

Use the team's authenticated private clone URL and pin a reviewed ref. A
branch is convenient while the team is testing; a commit SHA or release tag is
reproducible:

```sh
~/code/remote-dev-execution/scripts/install-skill.sh \
  --repo git@github.com:your-org/remote-dev-execution.git \
  --ref team-stable \
  --client claude
```

Do not place a private deploy key, access token, or private repository path in
the Skill files. Let the normal Git/SSH credential helper handle access.

## Configure a Project

Run the following from the VM project checkout. The file is local project
configuration, not Skill configuration:

```sh
cp ~/code/remote-dev-execution/assets/.dev-exec.env.example .dev-exec.env
chmod 600 .dev-exec.env
```

Edit it to contain the authoritative SSH alias and project path:

```sh
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine
DEV_EXEC_SHELL=/bin/zsh
```

Use an SSH alias from the normal user SSH config. Do not put a password, token,
private key, or real machine-specific values in this Skill repository. Add the
project file to the business repository's `.gitignore` (or use
`.git/info/exclude` for a local-only rule).

`dev-exec` searches from the caller's current directory upward and uses the
nearest `.dev-exec.env`. Process environment values override file values for
temporary changes:

```sh
DEV_EXEC_SHELL=/bin/sh ~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

For all variables and precedence rules, read
[references/configuration.md](references/configuration.md).

## Direct SSH: Complete Demo

This is the simplest topology when the VM can reach the authoritative machine.

### 1. Configure and test the SSH alias

On the VM, configure the alias in the normal `~/.ssh/config` using your own
host, user, and key values. The following is only a shape example:

```sshconfig
Host dev-machine
  HostName your-development-host
  User devuser
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

Test non-interactively before involving the Skill:

```sh
ssh dev-machine true
ssh dev-machine 'uname -a'
```

If either command prompts for a password or fails host-key verification, fix
ordinary SSH first. Do not disable host-key checking in the Skill.

### 2. Point the project at the authoritative checkout

From the VM project:

```sh
cat > .dev-exec.env <<'EOF'
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine
DEV_EXEC_SHELL=/bin/zsh
EOF
chmod 600 .dev-exec.env
```

The `DEV_EXEC_DIR` path is interpreted on the authoritative machine, not in
the VM. It must be absolute.

### 3. Run the smallest useful authoritative check

```sh
~/code/remote-dev-execution/scripts/dev-exec -- npm test -- --runInBand
```

For pipelines or shell operators, pass one quoted command string:

```sh
~/code/remote-dev-execution/scripts/dev-exec \
  'npm test -- --runInBand | tee /tmp/project-test.log'
```

The wrapper changes to `DEV_EXEC_DIR`, starts `DEV_EXEC_SHELL -lc`, writes
remote stdout/stderr directly to the caller, and returns the remote command's
exit status.

## Mutagen: Optional, but Source Freshness Is Mandatory

### When you do not need Mutagen

Do not install or configure Mutagen when:

- the VM and authoritative machine use the same shared or mounted checkout;
- the VM path is already the authoritative checkout; or
- another synchronization tool has a documented, verified completion step.

In these cases, leave `DEV_EXEC_MUTAGEN_SESSION` unset, but still verify that
the authoritative checkout contains the current source before trusting a test
result.

### When Mutagen is useful

Use Mutagen when the VM and Mac/workstation have separate checkouts and the VM
is the editing side. Create and configure the session according to your team's
sync policy. A generic two-endpoint example is:

```sh
mutagen sync create \
  --name=project-sync \
  /absolute/path/to/project/on/vm \
  ssh://dev-machine/absolute/path/to/project/on/authoritative-machine
```

Confirm that the session is healthy and flush it manually once:

```sh
mutagen sync list
mutagen sync flush -- project-sync
```

Then add only the session name to the VM project's ignored `.dev-exec.env`:

```sh
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine
DEV_EXEC_SHELL=/bin/zsh
DEV_EXEC_MUTAGEN_SESSION=project-sync
DEV_EXEC_MUTAGEN_BIN=mutagen
```

Every `dev-exec` call now flushes `project-sync` before opening SSH. If the
flush returns non-zero, the command is not started. Resolve the sync error
instead of bypassing the preflight.

The flush runs where `dev-exec` runs. For a VM-hosted Claude session, install
Mutagen and create the session in the VM, and make sure the VM can use the SSH
alias required by that session. Installing Mutagen only on the Mac does not
satisfy the VM-side preflight.

Mutagen does not make remote generated files automatically safe to keep. Before
running formatters, generators, migrations, installs, or snapshot updates,
decide which checkout owns those changes and how they return to the editing
environment.

## Non-Admin macOS Reverse Relay

Use this topology when the authoritative environment is a Mac, Claude runs in
a VM, and the VM cannot connect inbound to the Mac because Remote Login cannot
be enabled or administrator access is unavailable.

```text
VM: dev-exec / ssh rde-mac-dev
        -> VM 127.0.0.1:22022
        -> reverse SSH forward created by the Mac
        -> Mac 127.0.0.1:22022
        -> user-owned sshd
        -> Mac project, toolchain, services, and runtime
```

There are two intentionally different SSH aliases:

- `dev-vm` is used on the Mac to reach the VM and create the reverse tunnel.
- `rde-mac-dev` is installed in the VM and points back through that tunnel to
  the Mac.

### One-command setup on the Mac

First confirm that the Mac can already authenticate to the VM without a
password prompt:

```sh
ssh dev-vm true
```

Then run:

```sh
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm \
  --project /absolute/path/to/project/on/vm \
           /absolute/path/to/project/on/mac \
  --shell /bin/zsh \
  --mutagen project-sync
```

Replace all paths, aliases, shell, and session values with local values. The
`--project` mapping is optional. It generates the VM project's `.dev-exec.env`
and adds that file to the VM checkout's local Git exclude when possible. If you
omit `--project`, create the file manually on the VM as shown below.

Setup performs these operations without administrator access:

1. Creates a dedicated VM Ed25519 key if needed.
2. Retrieves only the VM public key to authorize the Mac's user-owned `sshd`.
3. Creates a loopback-only Mac `sshd` and starts the reverse tunnel.
4. Installs a managed VM SSH alias and exact relay host-key trust entry.
5. Installs `dev-exec` at `~/.local/share/remote-dev-execution/dev-exec` on the
   VM and creates `~/.local/bin/dev-exec` only when that name is unused.
6. Verifies a VM-to-Mac command through the relay.

It does not synchronize separate project checkouts unless `--mutagen` or
another verified mechanism is configured. It does not grant access only to one
project: the VM can open a shell as the current Mac user while the relay is
active, so use it only with a trusted VM.

### Start, inspect, and stop the relay

`setup` starts the relay. After a Mac sleep, network change, or VM restart,
inspect and restart it as needed:

```sh
~/code/remote-dev-execution/scripts/dev-relay status
~/code/remote-dev-execution/scripts/dev-relay stop
~/code/remote-dev-execution/scripts/dev-relay start
```

For a terminal-supervised foreground process:

```sh
~/code/remote-dev-execution/scripts/dev-relay foreground
```

`foreground` owns the relay for that terminal and cleans up the user `sshd`
when the process exits. Do not run it while a background tunnel is active.

### Verify from the VM

The setup command normally installs the SSH alias automatically. A direct
check makes the direction explicit:

```sh
ssh rde-mac-dev 'uname -a'
```

From the VM project, use the installed wrapper:

```sh
~/.local/share/remote-dev-execution/dev-exec -- npm test
```

Without `--project`, create the ignored file on the VM:

```sh
cat > .dev-exec.env <<'EOF'
DEV_EXEC_HOST=rde-mac-dev
DEV_EXEC_DIR=/absolute/path/to/project/on/mac
DEV_EXEC_SHELL=/bin/zsh
# Optional when the VM and Mac checkouts are separate:
# DEV_EXEC_MUTAGEN_SESSION=project-sync
EOF
chmod 600 .dev-exec.env
```

### Interactive debugging and debug ports

`dev-exec` is for non-interactive commands. Use direct SSH with a TTY for a
shell, REPL, or terminal debugger:

```sh
ssh -t rde-mac-dev \
  'cd /absolute/path/to/project/on/mac && exec /bin/zsh -l'
```

To expose selected same-numbered debug ports on the VM loopback, add them to
the Mac relay configuration at
`~/.config/remote-dev-execution/relay.env`:

```sh
DEV_RELAY_DEBUG_PORTS="3000 5005 9229"
```

Restart the relay and bind the Mac-side debugger/service to `127.0.0.1`.
Those ports are forwarded only between loopback interfaces; they are not
published on the LAN.

For manual relay setup, generated VM config, security details, and limitations,
read [references/reverse-relay.md](references/reverse-relay.md).

## End-to-End Demos

### Demo A: direct SSH, shared checkout

```sh
# Run inside the VM project.
printf '%s\n' \
  'DEV_EXEC_HOST=dev-machine' \
  'DEV_EXEC_DIR=/absolute/path/to/shared/project' \
  'DEV_EXEC_SHELL=/bin/zsh' > .dev-exec.env
chmod 600 .dev-exec.env

ssh dev-machine true
~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

No Mutagen session is needed because both sides use the same checkout.

### Demo B: separate checkouts with Mutagen

```sh
# Run once after configuring the session according to your sync policy.
mutagen sync flush -- project-sync

# Run inside the VM project.
printf '%s\n' \
  'DEV_EXEC_HOST=dev-machine' \
  'DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine' \
  'DEV_EXEC_MUTAGEN_SESSION=project-sync' > .dev-exec.env
chmod 600 .dev-exec.env

~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

The wrapper flushes before every run and stops if the flush fails.

### Demo C: VM Claude to a non-admin Mac

```sh
# On the Mac: install the relay and generate VM project config.
ssh dev-vm true
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm \
  --project /absolute/path/to/project/on/vm \
           /absolute/path/to/project/on/mac \
  --shell /bin/zsh \
  --mutagen project-sync

# In the VM project: verify the reverse path and run the Mac-side test.
ssh rde-mac-dev 'uname -a'
~/.local/share/remote-dev-execution/dev-exec -- npm test
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `DEV_EXEC_HOST is required` | Run from the intended project tree or export the required values. |
| `configuration not found` | Create `.dev-exec.env` in the project or a parent directory. |
| SSH prompts for a password | Fix the ordinary SSH alias and keychain first; the wrapper is non-interactive. |
| Remote directory fails | Confirm `DEV_EXEC_DIR` is absolute and exists on the authoritative machine. |
| Mutagen flush fails | Run `mutagen sync list` and `mutagen sync flush -- SESSION`; do not bypass the preflight. |
| Relay is stopped | On the Mac run `dev-relay status`, then `stop` and `start`. |
| VM host-key failure | Re-run `dev-relay print-vm-config` or setup and install the exact generated trust entry. Never disable strict checking. |
| Debugger cannot connect | Configure only the required `DEV_RELAY_DEBUG_PORTS`, bind the service to loopback, and restart the relay. |
| macOS audit/login warnings | A non-root user `sshd` may lack system audit databases; command and TTY sessions can still work. |

## Security and Redaction Checklist

Keep these outside Git:

- `.dev-exec.env` and `relay.env`;
- SSH private keys, `known_hosts` material, and relay state;
- usernames, hostnames, IP addresses, absolute project paths, tokens, and
  passwords;
- logs or command output containing credentials or personal data.

Before an internal or public push, run a repository scan. Example values such
as `dev-machine`, `dev-vm`, `rde-mac-dev`, `127.0.0.1`, and
`/absolute/path/...` are intentionally generic:

```sh
git status --short --ignored
git grep -n -I -E \
  '(/Users/|/home/|/var/folders|ssh-(rsa|ed25519)|BEGIN .*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]+|Bearer [A-Za-z0-9._-]+)' \
  -- . ':!README.md' ':!README.zh-CN.md' || true
```

If a real secret was ever committed, revoke or rotate it first. Removing the
line from the latest commit is not sufficient; use an approved history-rewrite
process before public distribution.

## Update, Uninstall, and Release

Update a clean checkout to a reviewed ref:

```sh
~/code/remote-dev-execution/scripts/install-skill.sh \
  --repo https://github.com/lajidonggua/remote-dev-execution.git \
  --ref main \
  --client claude
```

To uninstall, verify that the user-level target is a symlink to the canonical
checkout and remove only that link. Keep or remove the checkout separately.

For public distribution, merge reviewed changes, wait for the `Validate`
workflow, create an annotated tag such as `v0.1.0`, and have users install the
tag instead of an unreviewed moving branch. Do not use `curl | sh`; clone the
reviewed repository first so the installer and selected ref are visible before
they run.

## Validate Changes

Run the same checks used by CI:

```sh
sh -n scripts/dev-exec scripts/dev-relay scripts/install-skill.sh \
  tests/test-dev-exec.sh tests/test-install-skill.sh
tests/test-dev-exec.sh
tests/test-install-skill.sh
```

The official Skill metadata validator additionally requires Python `PyYAML`.

## References and License

- [Configuration reference](references/configuration.md)
- [Non-admin macOS reverse relay reference](references/reverse-relay.md)
- [MIT License](LICENSE)
