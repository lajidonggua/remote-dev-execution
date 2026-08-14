# remote-dev-execution

An Agent Skill for editing source in a lightweight AI environment while running authoritative build, test, runtime, Docker, and debugging commands on an SSH-accessible development machine.

The repository is the canonical copy. Codex and Claude consume it through user-level symlinks, so updates are maintained once.

## What It Does

- Finds the nearest `.dev-exec.env` from the current directory upward.
- Optionally flushes a Mutagen session before remote execution.
- Refuses to execute through SSH when synchronization fails.
- Starts commands in the configured remote project directory and shell.
- Streams stdout and stderr unchanged and returns the command's SSH exit status.
- Guides an AI agent to choose validation and debugging commands from the project's own instructions and build metadata.
- Supports a non-admin macOS reverse relay when a VM cannot connect inbound to the Mac.

When Mutagen is not configured, the user or agent must confirm that the remote path is a shared checkout or is synchronized by another mechanism. The wrapper cannot infer source freshness.

## Requirements

- A POSIX-compatible local shell.
- SSH access through a configured host alias.
- Mutagen only when pre-execution synchronization is enabled.

Keep usernames, network addresses, ports, keys, credentials, and machine-specific paths outside this repository.

## Install

Clone this repository to its canonical location:

```sh
git clone https://github.com/lajidonggua/remote-dev-execution.git ~/code/remote-dev-execution
```

Link that canonical copy into each supported user-level Skill directory:

```sh
mkdir -p ~/.agents/skills ~/.claude/skills
ln -s ~/code/remote-dev-execution ~/.agents/skills/remote-dev-execution
ln -s ~/code/remote-dev-execution ~/.claude/skills/remote-dev-execution
```

Before creating a link, inspect any existing target. Do not replace a real directory or a link to another location without reviewing it first.

## Configure a Project

```sh
cp ~/code/remote-dev-execution/assets/.dev-exec.env.example .dev-exec.env
```

Replace the placeholders and add `.dev-exec.env` to the business project's `.gitignore`. See [references/configuration.md](references/configuration.md) for variable definitions, precedence, security, and troubleshooting.

## Run Commands

Use argument form for ordinary commands:

```sh
~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

Use one quoted string without `--` for pipelines, redirections, expansions, or other remote shell syntax:

```sh
~/code/remote-dev-execution/scripts/dev-exec 'npm test | tee /tmp/test.log'
```

The wrapper searches for `.dev-exec.env` relative to the current working directory, not relative to the Skill repository.

## Non-Admin Mac Relay

When macOS Remote Login cannot be enabled, run a loopback-only user sshd and let the Mac initiate a reverse SSH tunnel to the VM:

```sh
ssh dev-vm true
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm
```

Replace `dev-vm` with a trusted, passwordless VM SSH alias. Setup creates the local relay configuration when absent, provisions a dedicated VM key, initializes and starts the user sshd, installs managed VM SSH trust/config, installs `dev-exec` on the VM, and verifies the return path. It is safe to rerun and does not require `sudo`, port 22, firewall changes, or an inbound Mac address.

Use this only with a VM trusted to open a shell as the current Mac user. Connectivity setup does not synchronize separate project checkouts; configure Mutagen or another verified sync mechanism before accepting remote results.

To avoid editing `.dev-exec.env` by hand, rerun setup with both project paths:

```sh
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm \
  --project /absolute/path/to/project/on/the/vm \
           /absolute/path/to/project/on/the/mac \
  --shell /bin/zsh \
  --mutagen workspace
```

`--project` is optional but must receive both paths explicitly because VM and Mac checkout paths cannot be inferred safely. Setup writes a marked `.dev-exec.env` in the VM project, keeps it out of Git's local exclude when possible, and is safe to rerun. Omit `--mutagen` when another source-sync mechanism is already verified.

Run authoritative commands from that VM project with the installed wrapper:

```sh
~/.local/share/remote-dev-execution/dev-exec -- npm test
```

See [references/reverse-relay.md](references/reverse-relay.md) for project configuration, manual setup, interactive debugging, debug-port forwarding, lifecycle, and policy limitations.

## Update

```sh
git -C ~/code/remote-dev-execution pull --ff-only
```

Both Skill installations immediately see the updated canonical copy.

## License

MIT
