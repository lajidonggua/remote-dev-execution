# Non-Admin macOS Reverse Relay

Use this topology when the authoritative development environment is a Mac where the current user cannot enable system Remote Login, accept inbound network connections, or obtain administrator rights.

## Contents

- [Topology](#topology)
- [Security Model](#security-model)
- [Prerequisites](#prerequisites)
- [One-Command Setup](#one-command-setup)
- [Manual Setup](#manual-setup)
- [Execution and Debugging](#execution-and-debugging)
- [Lifecycle](#lifecycle)
- [Troubleshooting](#troubleshooting)
- [Limitations and Alternatives](#limitations-and-alternatives)

## Topology

The Mac initiates every network-facing connection:

```text
VM dev-exec / ssh
        |
        v
VM 127.0.0.1:22022
        |
        | reverse SSH forwarding created by the Mac
        v
Mac 127.0.0.1:22022
        |
        v
user-owned sshd -> Mac shell, toolchain, services, and project
```

The user-owned `sshd` binds only a high loopback port. It does not enable macOS Remote Login, bind port 22, change the firewall, or require `sudo`.

## Security Model

`dev-relay` generates a private sshd configuration with these defaults:

- Listen only on Mac `127.0.0.1` and a port from 1024 to 65535.
- Accept exactly the dedicated VM Ed25519 public key installed by `dev-relay init`.
- Disable passwords, keyboard-interactive authentication, PAM, agent forwarding, TCP forwarding, X11, tunnels, user environment injection, and user SSH rc files.
- Allow TTY allocation for interactive debugging.
- Bind the VM end of every reverse forward to VM `127.0.0.1`.
- Require the Mac to verify the VM host key before establishing the outer tunnel.
- Require the VM to verify the generated Mac relay host key.

Keep both private keys on the machine that generated them. A VM with multiple users still exposes its loopback listener to those users, but the Mac relay requires the dedicated private key.

The dedicated VM key authenticates as the current Mac user and permits commands and TTY sessions while the relay is active. Use this design only with a VM you trust at that level. The relay does not confine access to one project directory.

## Prerequisites

- macOS has `/usr/sbin/sshd`, `/usr/bin/ssh`, and `/usr/bin/ssh-keygen`.
- The Mac user can already SSH outward to a VM alias such as `dev-vm`.
- The outer VM alias does not define unrelated `LocalForward`, `RemoteForward`, or `DynamicForward` entries. Use a dedicated alias or `DEV_RELAY_OUTER_SSH_CONFIG` when necessary.
- The VM SSH server permits remote forwarding. Most OpenSSH servers do by default.
- The VM account uses a POSIX-compatible login shell such as `sh`, Bash, Zsh, Dash, or Ksh. Automated setup checks this before provisioning.
- Both relay ports are unused high ports.

The VM does not need to reach the Mac network address. NAT, a changing Mac address, and inbound firewall restrictions do not affect this topology.

## One-Command Setup

First confirm that the Mac already trusts the VM host key and can authenticate without an interactive password prompt:

```sh
ssh dev-vm true
```

Then run on the Mac:

```sh
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm --client claude
```

Replace `dev-vm` with the Mac's trusted VM SSH alias. On first use, `setup` creates the local relay configuration with loopback-only high-port defaults. It then:

1. Generates a dedicated Ed25519 relay key on the VM when absent.
2. Retrieves only that key's public half and initializes the Mac user sshd.
3. Starts the reverse tunnel.
4. Installs a managed VM SSH snippet and exact Mac relay host key.
5. Installs `dev-exec` at `~/.local/share/remote-dev-execution/dev-exec` on the VM and creates `~/.local/bin/dev-exec` when that name is unused.
6. Installs this Skill for the selected VM Agent client using a canonical Git checkout and user-level link.
7. Verifies VM-to-Mac authentication through the relay.

To generate a project configuration in the same operation, provide both checkout paths explicitly:

```sh
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm \
  --client claude \
  --project /absolute/path/to/project/on/the/vm \
           /absolute/path/to/project/on/the/mac \
  --shell /bin/zsh
```

See [Relay Setup Options](configuration.md#relay-setup-options) for every value,
accepted `--client` choice, and how to use `--mutagen` when a reviewed session
already exists.

The `--project` mapping writes a marked `.dev-exec.env` in the VM project, adds it to Git's local exclude when possible, and can be repeated safely. It refuses to replace a symlink or an unmarked existing file. `--shell` and `--mutagen` are optional. Existing managed Mutagen assignments are preserved on repeat unless `--mutagen` replaces the session or `--clear-mutagen` explicitly removes them. Both paths remain explicit because setup cannot safely infer which Mac checkout is authoritative.

If setup reports an unmanaged project configuration, it has stopped before changing relay state. Keep the existing file and rerun without `--project` when it is already correct, or review and move it to a backup before asking setup to generate a managed file.

The command is safe to rerun. It replaces only its named managed SSH snippet and dedicated host-key entry, and attempts to restore an already-running relay if a later setup step fails. It refuses conflicting relay keys, alias collisions, symlinked managed snippets or dedicated trust files, and incompatible configuration rather than silently replacing them. When `~/.local/bin/dev-exec` already belongs to something else, setup leaves it untouched and reports the managed wrapper's full path.

If you did not provide `--project`, create an ignored `.dev-exec.env` in each VM project containing the real Mac project path:

```sh
DEV_EXEC_HOST=rde-mac-dev
DEV_EXEC_DIR=/absolute/path/to/project/on/the/mac
DEV_EXEC_SHELL=/bin/zsh
```

Then execute from the VM project:

```sh
# Separate checkouts only: install and configure synchronization once.
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync

~/.local/share/remote-dev-execution/dev-exec doctor
```

Run a project test only after doctor reports delegated execution ready and source freshness is confirmed. If the relay already exists but the VM Agent cannot find the Skill, install only the missing Skill and restart the Agent:

```sh
~/code/remote-dev-execution/scripts/dev-relay install-skill --client claude
```

Use `--client codex` or `--client both` as appropriate. Add `--repo` and `--ref` when installing from an internal repository or pinning a reviewed release.

Relay setup establishes execution connectivity; it does not synchronize project files. If the VM and Mac use separate checkouts, run the bundled project-aware Mutagen helper or configure another mechanism with a blocking completion check before trusting remote results. For an existing session, add it as `DEV_EXEC_MUTAGEN_SESSION` or pass `--mutagen SESSION` during relay setup. `dev-exec` flushes the session, rejects disconnected endpoints, conflicts, and filesystem problems from structured state, and stops before SSH whenever freshness cannot be established. See [Mutagen Synchronization](mutagen.md).

Use the following manual procedure only when customizing keys, ports, paths, or trust installation, or when diagnosing a failed automated setup.

## Manual Setup

### 1. Generate a dedicated key on the VM

Run on the VM:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/remote-dev-mac -C remote-dev-mac
```

Do not copy `~/.ssh/remote-dev-mac` off the VM.

### 2. Create the Mac relay configuration

Run on the Mac:

```sh
mkdir -p ~/.config/remote-dev-execution
cp ~/code/remote-dev-execution/assets/.dev-relay.env.example \
  ~/.config/remote-dev-execution/relay.env
```

Edit `relay.env` and set `DEV_RELAY_VM_HOST` to an SSH alias that the Mac already trusts. Choose unused high local and remote ports. Do not place passwords, tokens, or private keys in this file.

### 3. Retrieve only the VM public key

Run on the Mac:

```sh
ssh dev-vm 'cat ~/.ssh/remote-dev-mac.pub' \
  > ~/.config/remote-dev-execution/vm-public-key.pub
```

Replace `dev-vm` with the configured outer VM alias. Verify the displayed fingerprint through an independent trusted channel when the VM identity is sensitive.

### 4. Initialize the user sshd

Run on the Mac:

```sh
~/code/remote-dev-execution/scripts/dev-relay init \
  ~/.config/remote-dev-execution/vm-public-key.pub
```

This creates a user-owned host key, `authorized_keys`, a restricted `sshd_config`, and logs below `~/.local/state/remote-dev-execution/relay` by default. The non-sensitive SSH control socket uses a short, ownership-checked `0700` directory below the macOS temporary runtime path.

When running more than one relay, assign each relay a distinct `DEV_RELAY_REMOTE_PORT`. If two relays must use the same remote port, give them distinct `DEV_RELAY_RUNTIME_DIR` values as well.

### 5. Start the relay

First confirm ordinary outbound SSH works without a password prompt:

```sh
ssh dev-vm true
```

Then start the loopback sshd and background reverse tunnel:

```sh
~/code/remote-dev-execution/scripts/dev-relay start
~/code/remote-dev-execution/scripts/dev-relay status
```

The VM SSH server sees a request equivalent to:

```sh
ssh -N -R 127.0.0.1:22022:127.0.0.1:22022 dev-vm
```

`dev-relay` also adds strict host-key checking, batch authentication, server-alive probes, failure checks, and a control socket.

### 6. Configure VM trust and alias

Run on the Mac:

```sh
~/code/remote-dev-execution/scripts/dev-relay print-vm-config \
  '~/.ssh/remote-dev-mac'
```

Add the printed `Host` block to the VM's `~/.ssh/config` and write the printed host-key line to the dedicated VM file `~/.ssh/remote-dev-execution/known_hosts`. The identity path in the command is interpreted on the VM.

Test from the VM:

```sh
ssh rde-mac-dev true
```

### 7. Configure each project on the VM

In the VM editing copy, use the printed alias:

```sh
DEV_EXEC_HOST=rde-mac-dev
DEV_EXEC_DIR=/absolute/path/to/project/on/the/mac
DEV_EXEC_SHELL=/bin/zsh
```

Keep these values in the project's ignored `.dev-exec.env`, never in this Skill repository.

## Execution and Debugging

### Batch validation

Run from the VM project:

```sh
~/code/remote-dev-execution/scripts/dev-exec doctor
~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

Skip the test when doctor reports failed delegated execution or unverified source freshness. The existing `dev-exec` stdout, stderr, exit-status, source-freshness, and Mutagen rules still apply. Use the privacy-safe prompt and observable checks in [Agent Execution Validation](agent-validation.md) when testing Agent behavior.

### Interactive shell or debugger

`dev-exec` intentionally preserves separate non-TTY streams. Use direct SSH when a debugger needs a terminal:

```sh
ssh -t rde-mac-dev \
  'cd /absolute/path/to/project/on/the/mac && exec /bin/zsh -l'
```

Start `lldb`, `jdb`, `gdb`, a REPL, or another terminal debugger inside that session.

### Debug protocol ports

Set same-numbered Mac ports explicitly in the Mac relay configuration:

```sh
DEV_RELAY_DEBUG_PORTS="3000 5005 9229"
```

Restart the relay. A service bound to Mac `127.0.0.1:9229` becomes reachable at VM `127.0.0.1:9229`. The port is not exposed on either machine's LAN interface.

Use only ports needed for the current workflow. `ExitOnForwardFailure` prevents a partially established relay when a requested VM port is unavailable.

## Lifecycle

```sh
dev-relay status
dev-relay stop
dev-relay start
```

`start` creates a background SSH control master. After sleep, a network change, or VM restart, run `status`; use `stop` followed by `start` if disconnected.

`foreground` keeps the outer SSH process attached to the terminal and cleans up the sshd it started on exit. It is suitable for a user-level supervisor or a terminal session that should own the relay:

```sh
dev-relay foreground
```

No system LaunchDaemon or administrator-owned service is required.

## Troubleshooting

- **`configuration not found`:** Copy the relay env example to the default config path or set `DEV_RELAY_CONFIG`.
- **`generated sshd configuration failed`:** Confirm the macOS OpenSSH server exists and inspect the generated paths and permissions.
- **Outer tunnel fails:** Run `ssh DEV_RELAY_VM_HOST true` on the Mac. Resolve host-key or public-key authentication first.
- **`remote port forwarding failed`:** Choose another high VM port, or ask the VM administrator whether `AllowTcpForwarding remote` is disabled.
- **VM reports host-key failure:** Re-run `print-vm-config` and install the exact generated host-key line. Do not disable strict checking.
- **Mac command fails but SSH works:** Confirm `DEV_EXEC_DIR`, the selected shell, PATH, project dependencies, and source freshness.
- **Agent cannot find the Skill:** Run `dev-relay install-skill` with the matching `--client`, then restart the Agent session.
- **Project config is unmanaged:** Preserve it and omit `--project`, or move it to a reviewed backup before rerunning setup. It is never overwritten automatically.
- **Doctor reports source freshness unverified:** Confirm that both sides use the same checkout or complete the configured external synchronization before testing.
- **macOS log mentions BSM audit or login records:** A non-root sshd may be unable to write system audit or login databases. This is expected when command and TTY sessions otherwise succeed.
- **Connection disappeared:** Run `status`, then `stop` and `start`. Inspect the sshd log path printed by `status`.

## Limitations and Alternatives

This approach still requires an SSH server on the VM that accepts the Mac's outbound connection and permits reverse forwarding. If the VM policy disables remote forwarding, a VM administrator must change that policy or provide an approved relay.

If endpoint security blocks even a loopback user-owned `/usr/sbin/sshd`, do not bypass that policy. Use an approved user-space SSH server, an organization-approved mesh/VPN product, or a pull-based local runner that retrieves signed jobs from the VM. Products that install system extensions or VPN services may still require administrator approval.

Never replace this loopback design with a user sshd bound to `0.0.0.0`, never expose it through a public tunnel, and never disable host-key verification to make setup appear successful.
