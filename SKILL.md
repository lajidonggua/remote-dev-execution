---
name: remote-dev-execution
description: Route environment-dependent development commands through the bundled dev-exec wrapper when source work happens in a VM, remote workspace, container, or other secondary environment but the authoritative build, test, runtime, Docker, services, platform SDKs, or dependencies live on another development machine. Use for remote validation or debugging, .dev-exec.env setup, SSH path or shell failures, optional Mutagen synchronization, and non-admin macOS reverse-relay setup when the VM cannot connect inbound to the Mac. Keep lightweight source work local, dynamically choose project-appropriate commands, and run authoritative checks in the real environment. Do not use for generic SSH or server administration, public tunneling, purely local runtime troubleshooting, or projects whose current environment is already authoritative.
---

# Remote Development Execution

Separate the environment where source is edited from the environment whose results are authoritative:

- Treat the current workspace as the **AI editing environment**. Inspect files, search code, edit source, and review diffs here.
- Treat `DEV_EXEC_HOST` plus `DEV_EXEC_DIR` as the **authoritative development environment**. Run commands there when their result depends on the real platform, toolchain, dependencies, containers, services, credentials, or runtime state.

Read [references/configuration.md](references/configuration.md) when configuring a project or diagnosing connection, path, shell, or synchronization problems.

Read [references/reverse-relay.md](references/reverse-relay.md) when a non-admin Mac cannot enable Remote Login or accept inbound VM connections. Use the bundled `scripts/dev-relay`; do not request `sudo`, change system Remote Login, bind a public interface, or weaken host-key checking.

## Establish Connectivity

- Use a direct SSH alias when the editing environment can already reach the authoritative development environment.
- Use the reverse relay when a Mac can connect outward to the VM but the VM cannot connect inbound to the Mac.
- Prefer `dev-relay setup VM_ALIAS` for initial or repeatable deployment. It provisions dedicated keys, managed VM SSH entries, the VM wrapper, the relay, and an end-to-end check without administrator access.
- When the VM and Mac project paths are known, add `--project VM_PROJECT_DIR MAC_PROJECT_DIR` (plus optional `--shell` and `--mutagen`) so setup generates the VM project's `.dev-exec.env` without manual editing. Keep both paths explicit; never infer an authoritative checkout.
- Run `dev-relay status` on the Mac before diagnosing `dev-exec` through a relay.
- Use `dev-exec` for non-interactive commands with separate stdout and stderr.
- Use direct `ssh -t` through the relay alias for an interactive shell or terminal debugger.
- Forward debug protocol ports only when the user explicitly configures them, and bind both ends to loopback.

## Choose Commands Dynamically

1. Inspect project instructions and manifests before choosing a command. Check files such as `AGENTS.md`, `CLAUDE.md`, `README`, package scripts, build files, CI configuration, and nearby tests.
2. Establish how current source reaches `DEV_EXEC_DIR` before trusting remote results.
   - When `DEV_EXEC_MUTAGEN_SESSION` is configured, rely on the wrapper's mandatory flush.
   - Otherwise, confirm that `DEV_EXEC_DIR` is the same shared checkout or that another synchronization mechanism has completed.
   - Stop if source freshness is unknown. Do not validate an arbitrary remote checkout.
3. Decide whether the command is environment-dependent and whether it mutates repository files.
   - Run source search, file inspection, edits, and diff review in the AI editing environment.
   - Run non-mutating builds, tests, package scripts, application checks, Docker operations, service-backed checks, platform-specific tools, and runtime debugging in the authoritative environment.
   - Run a local static check only when it is demonstrably independent of missing remote dependencies and platform state.
   - Do not automatically run installs, formatters, generators, snapshot updates, migrations, or other commands that may write repository files remotely. Establish explicit source ownership and round-trip synchronization first.
4. Select the smallest high-signal command for the current change. Prefer a focused test or package target first, then broaden validation when risk or shared behavior warrants it.
5. Execute the selected command from the project workspace with the bundled wrapper:

   ```sh
   /path/to/remote-dev-execution/scripts/dev-exec -- npm test
   ```

6. Use one quoted argument without `--` when the remote shell must interpret operators, pipelines, expansions, or redirections:

   ```sh
   /path/to/remote-dev-execution/scripts/dev-exec 'npm test -- --runInBand | tee /tmp/test.log'
   ```

7. Diagnose failures using the returned output and exit status. Edit source in the AI editing environment, then rerun the narrowest relevant authoritative command.

Do not hard-code a language, framework, build system, or test command in advance. Derive the command from the repository and the failure under investigation.

## Preserve the Environment Boundary

- Keep the repository in the AI editing environment as the source-editing copy unless the user explicitly chooses another ownership model.
- Do not accept remote results until the authoritative checkout is known to contain the current editing copy.
- Never treat a successful local build or test as authoritative when its dependencies or runtime belong to the remote environment.
- Never bypass a failed Mutagen flush. When synchronization fails, the wrapper does not start SSH; resolve synchronization first.
- Do not compensate for source drift or capture generated changes by silently editing the authoritative copy over SSH.
- Do not invent host aliases, usernames, addresses, remote paths, shell paths, or Mutagen session names. Use `.dev-exec.env`.
- Do not invent relay ports, VM key paths, or debug ports. Use the relay config and its generated VM SSH block.
- Preserve normal safety checks for destructive commands. Remote execution does not imply permission to make destructive or production changes.

## Interpret Results

The wrapper writes remote stdout and stderr directly to the caller and returns SSH's exit status, which reflects the remote command status when the connection succeeds. A Mutagen flush failure is also returned directly and prevents remote execution.

Distinguish code failures from environment failures:

- For compilation, assertion, lint, or application errors, inspect and edit the local source copy, then rerun remotely.
- For connection, missing directory, unavailable shell, or dependency-service errors, inspect project configuration and the authoritative environment before changing source.
- For synchronization errors, stop remote validation until the editing copy has been flushed successfully.
