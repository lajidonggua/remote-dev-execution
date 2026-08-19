# Configuration

Use a project-local `.dev-exec.env` to describe the authoritative development environment without placing machine-specific values in this Skill repository.

## Contents

- [Relay Setup Options](#relay-setup-options)
- [Lookup and Precedence](#lookup-and-precedence)
- [Variables](#variables)
- [File Format and Trust](#file-format-and-trust)
- [Command Semantics](#command-semantics)
- [Doctor and Trust Boundary](#doctor-and-trust-boundary)
- [Source Freshness and Ownership](#source-freshness-and-ownership)
- [Recommended Mutagen Setup](#recommended-mutagen-setup)
- [Mutagen Preflight](#mutagen-preflight)
- [Troubleshooting](#troubleshooting)

## Relay Setup Options

Use the setup command on the authoritative Mac when a reverse relay manages the Agent environment:

```sh
dev-relay setup VM_ALIAS \
  --client claude \
  --project AGENT_PROJECT_DIR AUTHORITATIVE_PROJECT_DIR \
  --shell /bin/zsh \
  --mutagen MUTAGEN_SESSION \
  --mutagen-host MUTAGEN_CONTROL_HOST \
  --mutagen-bin MUTAGEN_BIN
```

| Argument | Required? | Value and effect |
| --- | --- | --- |
| `VM_ALIAS` | Required for first setup | Existing Mac-side SSH alias for the Agent environment. It is stored in relay configuration. |
| `AGENT_PROJECT_DIR` | Required with `--project` | Existing absolute checkout path in the Agent environment. Setup writes `.dev-exec.env` here. |
| `AUTHORITATIVE_PROJECT_DIR` | Required with `--project` | Absolute checkout path used for delegated commands in the authoritative environment. It becomes `DEV_EXEC_DIR`. |
| `--client CLIENT` | Optional for `setup` | `CLIENT` must be `claude`, `codex`, or `both`. Installs or updates the canonical Skill checkout and selected user-level links in the Agent environment. Restart the Agent afterward. Standalone `install-skill` defaults to `claude`. |
| `--shell SHELL` | Optional; requires `--project` | Shell executable used for delegated commands. Setup uses the current user's shell when available; `dev-exec` otherwise defaults to `/bin/sh`. |
| `--mutagen SESSION` | Optional; requires `--project` | Existing Mutagen session name. By default the session is controlled locally; combine with `--mutagen-host` when its daemon runs in another approved environment. |
| `--mutagen-host HOST` | Optional; requires `--project` and `--mutagen` | SSH alias reachable from the Agent environment where the existing Mutagen daemon/session runs. Setup stores it as `DEV_EXEC_MUTAGEN_HOST`; preflight commands are executed there. |
| `--mutagen-bin BIN` | Optional; requires `--project` and `--mutagen` | Mutagen executable name or absolute path in the selected control environment. Setup stores it as `DEV_EXEC_MUTAGEN_BIN`; useful when non-interactive SSH has a minimal `PATH`. |
| `--clear-mutagen` | Optional; requires `--project` | Explicitly remove managed `DEV_EXEC_MUTAGEN_SESSION`, `DEV_EXEC_MUTAGEN_BIN`, and `DEV_EXEC_MUTAGEN_HOST` assignments from an existing generated project config. Cannot be combined with `--mutagen`. |
| `--repo REPOSITORY` | Optional; requires `--client` during `setup` | Git repository used for the canonical Skill checkout. |
| `--ref REF` | Optional; requires `--client` during `setup` | Branch, tag, or commit installed from the Skill repository. Defaults to `main`. |

`--client` does not select the authoritative destination; `DEV_EXEC_HOST` and `DEV_EXEC_DIR` do that. Omit `--client` only when the required Skill link is already installed or the Agent does not need this Skill.

`--mutagen` does not create a session or install Mutagen. Use it only with an existing session. When no session exists, generate the project config first without `--mutagen`, then run `scripts/setup-mutagen.sh --install --name SESSION` inside the Agent project. If the session already lives in another approved environment, pass both `--mutagen SESSION` and `--mutagen-host CONTROL_HOST`; the wrapper runs `mutagen version`, `sync list`, and `sync flush` on that control host over the configured SSH alias. See [Mutagen Synchronization](mutagen.md) for installation, ignores, session operation, and recovery. Omit Mutagen for a shared checkout or another synchronization mechanism that completes before every validation. Without any verified freshness mechanism, project tests must stop.

When setup rewrites a previously generated project configuration, it preserves
the existing Mutagen session, executable, and control-host assignments by
default. Pass `--mutagen` to replace the session, or `--clear-mutagen` to
remove those assignments intentionally. This avoids turning off the freshness
gate during a routine relay refresh.

## Lookup and Precedence

`dev-exec` starts at the caller's current directory and searches each parent directory for the nearest `.dev-exec.env`. This lets commands run from nested package or test directories.

For a relay-managed VM, the Mac setup command can generate the project file after the paths are confirmed:

```sh
~/code/remote-dev-execution/scripts/dev-relay setup VM_ALIAS \
  --client claude \
  --project /absolute/path/to/project/on/the/vm \
           /absolute/path/to/project/on/the/mac \
  --shell /bin/zsh \
  --mutagen SESSION
```

When the existing session is controlled in another approved environment, add
`--mutagen-host MUTAGEN_CONTROL_HOST` and, when `mutagen` is not on the
non-interactive `PATH`, `--mutagen-bin MUTAGEN_BIN` to the setup command. Do not
create a second session with the same checkout pair.

Both paths are required because their relationship is project-specific. The generated file is marked as managed, written with mode `0600`, replaced atomically on repeat setup, and refused when an unmarked file or symlink already exists. When the VM project is a Git checkout, setup adds `.dev-exec.env` to `.git/info/exclude` when that local file is writable. It never adds the project-specific path to this Skill repository.

If an unmarked `.dev-exec.env` already exists, setup stops before changing relay state. Preserve it by rerunning without `--project` when its values are already correct. Otherwise, review it, move it to a backup, and rerun setup. The command never overwrites an unmanaged file.

The file is optional when all required values are already exported in the process environment. Explicit process environment values take precedence over values loaded from the file, which supports temporary overrides:

```sh
DEV_EXEC_SHELL=/bin/zsh dev-exec doctor
```

An empty `DEV_EXEC_MUTAGEN_SESSION` environment value does not disable a non-empty project setting. This prevents an inherited empty variable from silently bypassing the configured synchronization preflight.

## Variables

| Variable | Required | Meaning |
|----------|----------|---------|
| `DEV_EXEC_HOST` | Yes | One SSH destination or alias. Prefer an alias configured in `~/.ssh/config`. |
| `DEV_EXEC_DIR` | Yes | Absolute project path in the authoritative development environment. |
| `DEV_EXEC_SHELL` | No | Remote shell executable used with `-lc`. Defaults to `/bin/sh`. |
| `DEV_EXEC_MUTAGEN_SESSION` | No | Mutagen sync session to flush and health-check before SSH execution. |
| `DEV_EXEC_MUTAGEN_BIN` | No | Mutagen executable name or path in the selected control environment. Defaults to `mutagen`. |
| `DEV_EXEC_MUTAGEN_HOST` | No | SSH alias for the environment that owns the Mutagen daemon/session. Leave unset when Mutagen runs where `dev-exec` runs. Requires `DEV_EXEC_MUTAGEN_SESSION`. |

Copy `assets/.dev-exec.env.example` into the business project's root as `.dev-exec.env`, then replace every placeholder locally. The root `.gitignore` pattern in this repository does not automatically protect other repositories, so add `.dev-exec.env` to each business project's ignore rules.

## File Format and Trust

The wrapper sources `.dev-exec.env` as POSIX shell syntax so quoted values work. Keep it to simple variable assignments:

```sh
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project
DEV_EXEC_SHELL=/bin/zsh
# Optional when the Mutagen session is controlled elsewhere.
# DEV_EXEC_MUTAGEN_SESSION=project-sync
# DEV_EXEC_MUTAGEN_HOST=sync-control
```

Treat the file as executable configuration:

- Use it only in repositories and directories you trust.
- Do not place tokens, passwords, private keys, or other secrets in it.
- Keep SSH connection details and credentials in the normal SSH configuration and keychain.
- Do not commit the project-specific file.

## Command Semantics

Use `--` and pass arguments for a normal command. The wrapper quotes every argument before the selected remote shell evaluates it, including when there is only one:

```sh
dev-exec -- npm test -- --runInBand
```

Pass one quoted string when shell syntax must be interpreted remotely:

```sh
dev-exec 'npm test | tee /tmp/test.log'
```

The remote command starts in `DEV_EXEC_DIR`. Remote stdout and stderr are not captured or rewritten, and the SSH process status is returned to the caller. The wrapper requires batch authentication and strict host-key checking; trust the alias with ordinary SSH before invoking it.

## Doctor and Trust Boundary

Run this from the configured project after setup or whenever execution provenance is uncertain:

```sh
dev-exec doctor
```

The default output is intentionally redacted:

| Output | Meaning |
| --- | --- |
| `configuration: valid` | Required values are present and the project configuration loaded successfully. |
| `synchronization tool: available` | The configured Mutagen executable can be resolved. |
| `synchronization session: available` | The configured session exists and its state can be queried. |
| `synchronization health: healthy` | The post-flush state has connected endpoints and no conflicts, session error, scan problems, or transition problems. |
| `synchronization preflight: passed` | The configured session flushed and passed its structured health check. |
| `source freshness: not verified` | No synchronization preflight is configured. Confirm a shared checkout or completed external sync before testing. |
| `authoritative execution: ready` | The configured destination accepted a non-interactive command in `DEV_EXEC_DIR` using the selected shell. |

The trusted `.dev-exec.env` declares which environment is authoritative. Doctor verifies that the wrapper reaches that declaration; it cannot independently decide that a different endpoint should be authoritative. Its exit status reflects configuration, synchronization, and delegated-execution failures. A missing synchronization preflight is reported in output but is not itself non-zero because a genuinely shared checkout needs no flush.

Use `dev-exec doctor --verbose` only for user-approved troubleshooting. Underlying synchronization or connection tools may print hosts, users, paths, operating-system details, or other infrastructure values.

## Source Freshness and Ownership

`dev-exec` cannot infer whether an unconfigured remote checkout contains the current local edits.

- With `DEV_EXEC_MUTAGEN_SESSION`, the wrapper flushes the named session and rejects unhealthy post-flush state before SSH. It invokes Mutagen locally by default, or through `DEV_EXEC_MUTAGEN_HOST` when that control host is configured.
- Without it, confirm that `DEV_EXEC_DIR` is the same shared checkout or that another synchronization mechanism has completed before accepting remote results.
- Stop when freshness is unknown.

Prefer non-mutating validation commands. Before running installs, formatters, code generators, snapshot updates, migrations, or any command that can modify repository files, decide which checkout owns those changes and how they will return to the AI editing environment. Do not leave authoritative source changes stranded remotely.

## Recommended Mutagen Setup

For separate checkouts, run this from the Agent project after `.dev-exec.env`
has been generated and the configured SSH alias is reachable:

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
```

The helper derives both endpoints from the existing project configuration,
creates a `two-way-safe` session, always ignores VCS metadata and
`.dev-exec.env`, writes the session name atomically, and runs doctor. Add
project-specific generated directories with repeated `--ignore PATH` options.
It refuses to rewrite an existing Mutagen assignment.

Run installation/session creation only as an explicit setup action. Daily
Agent validation should use the already configured `dev-exec` preflight.
Detailed installation, checksum, ignore, lifecycle, and conflict guidance is
in [Mutagen Synchronization](mutagen.md).

## Mutagen Preflight

When `DEV_EXEC_MUTAGEN_SESSION` is non-empty, the wrapper runs (locally by default):

```sh
mutagen sync flush -- SESSION
```

It waits for completion before opening SSH. A non-zero flush status is returned immediately, so a command is never run against a knowingly stale authoritative copy.

After a successful flush, the wrapper queries the selected session with a
structured Mutagen template and accepts only a fixed `ok` token. It stops
before SSH when either endpoint is disconnected, or when the state reports
conflicts, a last session error, scan problems, or transition problems. Mutagen
may complete a `two-way-safe` flush while retaining conflicts, so this second
check is mandatory.

The flush runs in the same environment as `dev-exec`. If Claude or Codex runs in
a VM, install Mutagen there and create the session there, or explicitly set
`DEV_EXEC_MUTAGEN_HOST` to an approved SSH alias where the existing session is
controlled. Installing Mutagen only in the authoritative environment without
that explicit control-host setting does not satisfy this preflight.

## Troubleshooting

- **Configuration not found:** Run from inside the intended project tree, or export the required variables explicitly.
- **SSH cannot connect:** Test the exact `DEV_EXEC_HOST` alias with the system SSH client and inspect `~/.ssh/config`.
- **Remote directory fails:** Confirm `DEV_EXEC_DIR` is absolute and exists on the authoritative machine.
- **Shell fails:** Set `DEV_EXEC_SHELL` to an executable available on the authoritative machine.
- **Mutagen executable is unavailable:** Install it where `dev-exec` runs, use `setup-mutagen.sh --install`, or set `DEV_EXEC_MUTAGEN_HOST` and correct `DEV_EXEC_MUTAGEN_BIN` for the approved control environment.
- **Mutagen session is unavailable:** Confirm `DEV_EXEC_MUTAGEN_SESSION` with `mutagen sync list -- SESSION` in its control environment; do not substitute an unreviewed session.
- **Mutagen health reports a disconnected endpoint, conflicts, or filesystem problems:** Inspect `mutagen sync list --long -- SESSION` as the user, restore the session, reconcile reported paths, and rerun doctor. Do not bypass the health gate.
