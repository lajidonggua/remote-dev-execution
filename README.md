# remote-dev-execution

An Agent Skill for a split development workflow:

```text
AI editing environment (VM, container, or secondary workspace)
        |
        | inspect and edit source locally
        v
dev-exec / SSH / recommended Mutagen sync for separate checkouts
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

## Quick Start: Relay Setup and Optional Sync Setup

For a non-admin Mac plus a VM-hosted Claude Code session, `dev-relay setup`
can provision the relay, install the VM command wrapper, install this Skill for
Claude, and generate the project's ignored configuration in one operation.

Confirm these two prerequisites first:

1. The Mac can already run `ssh VM_ALIAS true` without a password prompt.
2. Both project checkout paths are known. For separate checkouts, complete the
   Mutagen step below before running any project test.

Then run on the Mac from this canonical checkout:

```sh
~/code/remote-dev-execution/scripts/dev-relay setup VM_ALIAS \
  --client claude \
  --project /absolute/path/to/project/in/agent-environment \
            /absolute/path/to/project/in/authoritative-environment \
  --shell /bin/zsh
```

### Setup values and options

| Value or option | Required? | What to enter |
| --- | --- | --- |
| `VM_ALIAS` | Yes on first setup | An existing SSH alias on the Mac that reaches the Agent environment. `ssh VM_ALIAS true` must already succeed without interaction. |
| First `--project` value | Required when using `--project` | The absolute path to the checkout in the Agent environment. The directory must already exist. |
| Second `--project` value | Required when using `--project` | The absolute path to the authoritative checkout where builds, tests, services, and debugging run. |
| `--client CLIENT` | Optional, recommended on first setup | `claude`, `codex`, or `both`. It installs this Skill in the Agent environment. Restart that Agent after installation. |
| `--shell SHELL` | Optional | An executable shell in the authoritative environment, usually `/bin/zsh` or `/bin/sh`. Setup uses the current user's shell when available; `dev-exec` otherwise defaults to `/bin/sh`. |
| `--mutagen SESSION` | Optional | The exact name of an existing Mutagen session available where `dev-exec` runs. It requires `--project`; it is a session name, not a path or host. |
| `--clear-mutagen` | Optional | Explicitly remove the managed Mutagen session and executable settings from an existing generated project config. It requires `--project` and cannot be combined with `--mutagen`. |

`--client` controls Skill installation only; it does not choose the execution
destination. Use `claude` when Claude Code runs in the Agent environment,
`codex` for Codex, and `both` when both clients run there. Omit it when the
correct Skill link is already installed or when setup should configure only the
relay and wrapper. You can install it later with `dev-relay install-skill`.

`--mutagen` selects an existing session; it does not install Mutagen or create
one. When no session exists yet, omit that option during the first relay setup.
Then, from the generated Agent project, run:

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
```

This performs a user-level installation when necessary, creates a
`two-way-safe` session from the existing project mapping, updates the ignored
`.dev-exec.env`, and runs doctor. Every later `dev-exec` call flushes and
health-checks the session before delegated execution. Disconnected endpoints,
conflicts, filesystem problems, or a failed flush stop the project command
before SSH.

When a reviewed session already exists, pass its name with
`--mutagen EXISTING_SESSION` during relay setup instead. Omit Mutagen entirely
only for a true shared checkout or another synchronization preflight with a
blocking completion check. Separate checkouts with no verified synchronization
must not be tested.

When rerunning setup for an existing generated project config, the current
Mutagen session and executable settings are preserved unless `--mutagen` replaces
the session or `--clear-mutagen` explicitly removes them. This prevents a routine
relay refresh from silently disabling the source-freshness gate. Use
`--clear-mutagen` only after confirming that the project now uses a shared
checkout or another independently verified synchronization mechanism.

| Scenario | `--client` | `--mutagen` |
| --- | --- | --- |
| First setup for VM-hosted Claude, separate checkouts, no session yet | `claude` | Omit, then run `setup-mutagen.sh --install` in the Agent project |
| First setup with an existing reviewed Mutagen session | `claude` | Existing session name |
| First setup for VM-hosted Claude, one shared checkout | `claude` | Omit |
| Skill is already installed; project mapping is being refreshed | Omit | Use only when this project uses Mutagen |
| Claude and Codex both run in the Agent environment | `both` | Depends on checkout synchronization |

For an internal Skill repository or pinned release, add `--repo REPOSITORY` and
`--ref BRANCH_OR_TAG_OR_COMMIT`. During `setup`, these options require
`--client`; the selected ref must already contain the version to install.

The two project paths and the source-freshness strategy are the only required
project choices. Setup does not guess them because a wrong guess can produce a
successful test against stale or unrelated source.

After setup, start a new Claude/Codex session. From the project in the agent
environment, run:

```sh
~/.local/share/remote-dev-execution/dev-exec doctor
```

A test is ready to run only when source freshness is confirmed, either by a
successful preflight or by a reviewed shared-checkout guarantee, and doctor
reports `authoritative execution: ready`. If it instead reports
`source freshness: not verified`, connectivity works, but do not test current
edits until the shared checkout or external synchronization has been confirmed.

Invoke the Skill with a topology-neutral prompt:

```text
Use $remote-dev-execution to validate delegated execution and run the smallest relevant project check without exposing infrastructure details.
```

For an existing relay that installed only the wrapper, repair the missing VM
Skill installation from the Mac, then restart the agent:

```sh
~/code/remote-dev-execution/scripts/dev-relay install-skill --client claude
```

See [Agent execution validation](references/agent-validation.md) for the full
privacy-safe prompt and observable acceptance criteria.

## What This Repository Contains

- `SKILL.md`: instructions loaded by Codex or Claude when the Skill is active.
- `scripts/dev-exec`: project-aware command wrapper with a redacted doctor,
  config lookup, Mutagen flush and health checks, SSH execution, and
  exit-status preservation.
- `scripts/dev-relay`: user-owned macOS `sshd` plus a Mac-initiated reverse
  SSH tunnel. It does not require administrator privileges.
- `scripts/install-skill.sh`: safe canonical-checkout and user-level-link
  installer for Claude Code or Codex.
- `scripts/install-mutagen.sh`: checksum-verified, no-admin Mutagen installer
  for supported macOS and Linux environments.
- `scripts/setup-mutagen.sh`: project-aware session creation, config update,
  and integrated doctor check.
- `references/configuration.md`: `.dev-exec.env` behavior and source-freshness
  rules.
- `references/mutagen.md`: installation, session setup, ignores, health checks,
  operation, and recovery.
- `references/reverse-relay.md`: relay security model, manual setup, and
  troubleshooting details.
- `references/agent-validation.md`: privacy-safe Agent prompt and observable
  proof that project tests were delegated.
- `assets/*.example`: templates containing placeholders only.

The repository is the canonical copy. Do not put project paths, SSH hosts,
usernames, IP addresses, private keys, passwords, tokens, or other secrets in
this repository.

## Choose Your Topology

| Situation | Recommended path | Is Mutagen required? |
| --- | --- | --- |
| The VM can SSH directly to the authoritative machine and both use one shared checkout | Direct SSH + `.dev-exec.env` | No |
| The VM and authoritative machine have separate checkouts | Direct SSH + Mutagen | Recommended; another sync is valid only with a trusted blocking completion check |
| The authoritative machine is a Mac and the VM cannot connect inbound to it | `dev-relay setup` reverse relay | Only when the checkouts are separate |
| You need an interactive shell or terminal debugger | Relay/direct `ssh -t` | No, but source freshness still matters |

Mutagen is a synchronization tool, not an SSH replacement. This Skill uses it
as a mandatory preflight for separate checkouts: `dev-exec` flushes the session
and then rejects conflicts or filesystem problems from structured session
state before starting SSH. The wrapper does not decide which side wins a
conflict.

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
- Mutagen in the environment where `dev-exec` runs when separate checkouts use
  the recommended synchronization path. The bundled installer needs no
  administrator access.

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

### Claude Code activation and prompts

Claude Code uses the Skill description to decide whether the Skill is relevant to
the current request. This is semantic, on-demand activation, not a command
interceptor. Installing the Skill does not automatically install Mutagen, create
`.dev-exec.env`, run `doctor`, or prevent Claude from running a command directly
in the current workspace.

Without an explicit workflow prompt, a request that clearly mentions remote
validation may still activate the Skill, but activation is not guaranteed. A
vague request such as "fix this and run the tests" can therefore result in a
local test instead of an authoritative test. A successful local test is not
evidence that the configured development environment was used.

For predictable team behavior, add a project-level `CLAUDE.md` (or `AGENTS.md`)
to the agent workspace and commit this policy with the project:

```markdown
For this workspace:

- Treat the current workspace as the editing environment.
- Run tests, builds, linters, services, and runtime checks only through the project's dev-exec wrapper.
- Run `dev-exec doctor` before authoritative validation.
- If execution or source freshness cannot be verified, stop and report the issue.
- Never run environment-dependent commands directly in the current workspace.
```

Keep `.dev-exec.env` and other machine-specific values local and ignored; the
policy above contains no hostnames, usernames, paths, operating systems, or
transport details. Restart Claude Code, or start a new session, after installing
or updating the Skill or changing its project instructions.

For ordinary work, this short prompt is enough:

```text
Use the project's remote-dev-execution workflow for validation.
```

For a privacy-safe agent validation check, use the full prompt in
[references/agent-validation.md](references/agent-validation.md). It requires a
redacted `dev-exec doctor` check before the smallest relevant test and tells the
agent to report only project-relevant results. Do not include infrastructure
details in prompts just to force activation.

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
DEV_EXEC_SHELL=/bin/sh ~/code/remote-dev-execution/scripts/dev-exec doctor
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
```

If the command prompts for a password or fails host-key verification, fix
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
~/code/remote-dev-execution/scripts/dev-exec doctor
~/code/remote-dev-execution/scripts/dev-exec -- npm test -- --runInBand
```

Do not run the test when doctor reports failed execution or when source
freshness has not been confirmed.

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

Use Mutagen when the Agent and authoritative environments have separate
checkouts. It keeps Claude/Codex scans and edits on the Agent's local filesystem
instead of a high-latency network mount.

First create `.dev-exec.env` manually or with `dev-relay setup --project`.
Then run this once from the Agent project:

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
```

| Option | When to use it | Effect |
| --- | --- | --- |
| `--install` | Mutagen is not already available where `dev-exec` runs | Installs the pinned release into `~/.local/bin` without `sudo`. |
| `--name SESSION` | Recommended for a stable team convention | Names the new session. If omitted, the helper derives a project-local name. |
| `--ignore PATH` | A reproducible dependency, cache, or build directory must remain local | Adds one Mutagen ignore; repeat the option for additional paths. |
| `--version VERSION` | The team has reviewed a different installer version | Selects the version used with `--install`. |
| `--verbose` | User-approved setup troubleshooting only | Shows underlying Mutagen output, which may contain endpoints and paths. |

The helper installs a pinned release into `~/.local/bin` without `sudo` when
needed, verifies the official release checksum, derives both endpoints from
the nearest `.dev-exec.env`, creates a `two-way-safe` session, writes the
session setting back atomically, keeps the config in Git's local exclude, and
runs doctor. It refuses to continue if `.dev-exec.env` is already tracked.

To install without creating a session, run:

```sh
~/code/remote-dev-execution/scripts/install-mutagen.sh
~/.local/bin/mutagen version
```

On an environment where Homebrew is already approved, use
`brew install mutagen-io/mutagen/mutagen` instead. Install in the environment
where `dev-exec` runs, not only in the authoritative environment.
The Mutagen daemon starts on demand; normally there is no separate service to
start. After a restart or network change, rerun doctor.

VCS metadata and `.dev-exec.env` are always ignored. Add only reproducible,
project-specific dependency or build directories that should remain local:

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync \
  --ignore node_modules \
  --ignore build
```

Do not copy these ignores blindly, and never ignore source, lockfiles,
migrations, fixtures, or reviewed generated artifacts. The authoritative
environment must provision its own ignored dependencies.

For an existing session, configure its exact name directly:

```sh
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine
DEV_EXEC_SHELL=/bin/zsh
DEV_EXEC_MUTAGEN_SESSION=project-sync
DEV_EXEC_MUTAGEN_BIN=mutagen
```

Every `dev-exec` call now flushes the session and queries structured session
health before opening SSH. It stops on a missing session, disconnected
endpoints, conflicts, session errors, scan problems, transition problems, or a
failed flush. This second
check matters because a `two-way-safe` flush can complete while preserving a
conflict.

Healthy doctor output contains `synchronization tool: available`,
`synchronization session: available`, `synchronization health: healthy`, and
`synchronization preflight: passed` before `authoritative execution: ready`.

Mutagen and its session must exist where `dev-exec` runs. Installing it only in
the authoritative environment does not satisfy the Agent-side preflight.

Mutagen does not make remote generated files automatically safe to keep. Before
running formatters, generators, migrations, installs, or snapshot updates,
decide which checkout owns those changes and how they return to the editing
environment.

See [Mutagen synchronization](references/mutagen.md) for standalone
installation, version pinning, existing-session configuration, ignores,
operation, conflict recovery, and security details.

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
  --client claude \
  --project /absolute/path/to/project/on/vm \
           /absolute/path/to/project/on/mac \
  --shell /bin/zsh
```

Replace all paths, aliases, shell, and session values with local values. The
`--project` mapping is optional. It generates the VM project's `.dev-exec.env`
and adds that file to the VM checkout's local Git exclude when possible. If you
omit `--project`, create the file manually on the VM as shown below. `--client`
installs this Skill in the environment where the Agent runs.

Setup performs these operations without administrator access:

1. Creates a dedicated VM Ed25519 key if needed.
2. Retrieves only the VM public key to authorize the Mac's user-owned `sshd`.
3. Creates a loopback-only Mac `sshd` and starts the reverse tunnel.
4. Installs a managed VM SSH alias and exact relay host-key trust entry.
5. Installs `dev-exec` at `~/.local/share/remote-dev-execution/dev-exec` on the
   VM and creates `~/.local/bin/dev-exec` only when that name is unused.
6. Installs a canonical Git checkout and user-level Skill link for the selected
   Agent client.
7. Verifies a VM-to-Mac command through the relay.

It does not synchronize separate project checkouts by itself. After first
setup, run `setup-mutagen.sh --install` in the VM project, pass an already
reviewed session with `--mutagen`, or use another verified mechanism. The relay
does not grant access only to one project: the VM can open a shell as the
current Mac user while it is active, so use it only with a trusted VM.

When repeating setup, omit `--mutagen` to preserve the existing managed session.
Use `--clear-mutagen` only when intentionally moving to a shared checkout or a
different verified freshness mechanism.

For a relay created by an earlier version, install only the missing Agent Skill
without rebuilding the relay:

```sh
~/code/remote-dev-execution/scripts/dev-relay install-skill --client claude
```

Use `--repo` and `--ref` with either command for an internal repository or a
reviewed release. Restart the Agent afterward so it discovers the Skill.

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

Setup already performs a raw end-to-end relay check. For normal user and Agent
verification, run the redacted doctor command from the VM project:

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync

~/.local/share/remote-dev-execution/dev-exec doctor
```

Run the setup helper only for separate checkouts and only once. Skip it for a
reviewed shared checkout or when an existing session was supplied to relay
setup.

Doctor proves that the wrapper reached the environment declared by the trusted
project configuration. It does not independently decide whether that endpoint
is authoritative or whether an unconfigured separate checkout is current.
Run a project test only after the endpoint and source-freshness declarations
have been reviewed. Use raw `ssh` probes only during user-approved verbose
troubleshooting because they can reveal infrastructure details.

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
~/code/remote-dev-execution/scripts/dev-exec doctor
~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

No Mutagen session is needed because both sides use the same checkout.

### Demo B: separate checkouts with Mutagen

```sh
# Run inside the VM project.
printf '%s\n' \
  'DEV_EXEC_HOST=dev-machine' \
  'DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine' > .dev-exec.env
chmod 600 .dev-exec.env

# Install, create the session, update config, and run doctor once.
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync \
  --ignore PROJECT_GENERATED_DIRECTORY

~/code/remote-dev-execution/scripts/dev-exec doctor
~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

Remove `--ignore PROJECT_GENERATED_DIRECTORY` when no additional ignore is
needed. The wrapper flushes and checks session health before every run.

### Demo C: VM Claude to a non-admin Mac

```sh
# On the Mac: install the relay and generate VM project config.
ssh dev-vm true
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm \
  --client claude \
  --project /absolute/path/to/project/on/vm \
           /absolute/path/to/project/on/mac \
  --shell /bin/zsh

# In the VM project: configure synchronization once, then run the test.
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
~/.local/share/remote-dev-execution/dev-exec doctor
~/.local/share/remote-dev-execution/dev-exec -- npm test
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `DEV_EXEC_HOST is required` | Run from the intended project tree or export the required values. |
| `configuration not found` | Create `.dev-exec.env` in the project or a parent directory. |
| SSH prompts for a password | Fix the ordinary SSH alias and keychain first; the wrapper is non-interactive. |
| Remote directory fails | Confirm `DEV_EXEC_DIR` is absolute and exists on the authoritative machine. |
| Mutagen executable is unavailable | Run `setup-mutagen.sh --install`, or correct `DEV_EXEC_MUTAGEN_BIN` where `dev-exec` runs. |
| Mutagen session is unavailable | Confirm `DEV_EXEC_MUTAGEN_SESSION` with `mutagen sync list -- SESSION`; do not select an unrelated session. |
| Mutagen health reports a disconnected endpoint, conflicts, or filesystem problems | Inspect `mutagen sync list --long -- SESSION`, restore the session, reconcile affected files, and rerun doctor. Do not bypass the health gate. |
| Doctor reports `source freshness: not verified` | Confirm a shared checkout or complete the external sync before testing; connectivity alone is insufficient. |
| Setup finds an unmanaged `.dev-exec.env` | Keep it and rerun without `--project`, or move it to a backup after review and rerun setup. It is never overwritten automatically. |
| The Agent cannot find this Skill | Run `dev-relay install-skill` with the matching `--client`, then restart the Agent. |
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
  scripts/install-mutagen.sh scripts/setup-mutagen.sh \
  tests/test-dev-exec.sh tests/test-dev-relay.sh tests/test-install-skill.sh \
  tests/test-install-mutagen.sh tests/test-setup-mutagen.sh \
  tests/test-relay-embedded.sh
tests/test-dev-exec.sh
tests/test-dev-relay.sh
tests/test-install-skill.sh
tests/test-install-mutagen.sh
tests/test-setup-mutagen.sh
tests/test-relay-embedded.sh
```

The official Skill metadata validator additionally requires Python `PyYAML`.

## References and License

- [Configuration reference](references/configuration.md)
- [Mutagen synchronization](references/mutagen.md)
- [Non-admin macOS reverse relay reference](references/reverse-relay.md)
- [Agent execution validation](references/agent-validation.md)
- [MIT License](LICENSE)
