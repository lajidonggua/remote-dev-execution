# Configuration

Use a project-local `.dev-exec.env` to describe the authoritative development environment without placing machine-specific values in this Skill repository.

## Contents

- [Lookup and Precedence](#lookup-and-precedence)
- [Variables](#variables)
- [File Format and Trust](#file-format-and-trust)
- [Command Semantics](#command-semantics)
- [Doctor and Trust Boundary](#doctor-and-trust-boundary)
- [Source Freshness and Ownership](#source-freshness-and-ownership)
- [Mutagen Preflight](#mutagen-preflight)
- [Troubleshooting](#troubleshooting)

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
| `DEV_EXEC_MUTAGEN_SESSION` | No | Mutagen sync session to flush before SSH execution. |
| `DEV_EXEC_MUTAGEN_BIN` | No | Mutagen executable name or path. Defaults to `mutagen`. |

Copy `assets/.dev-exec.env.example` into the business project's root as `.dev-exec.env`, then replace every placeholder locally. The root `.gitignore` pattern in this repository does not automatically protect other repositories, so add `.dev-exec.env` to each business project's ignore rules.

## File Format and Trust

The wrapper sources `.dev-exec.env` as POSIX shell syntax so quoted values work. Keep it to simple variable assignments:

```sh
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project
DEV_EXEC_SHELL=/bin/zsh
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

The remote command starts in `DEV_EXEC_DIR`. Remote stdout and stderr are not captured or rewritten, and the SSH process status is returned to the caller.

## Doctor and Trust Boundary

Run this from the configured project after setup or whenever execution provenance is uncertain:

```sh
dev-exec doctor
```

The default output is intentionally redacted:

| Output | Meaning |
| --- | --- |
| `configuration: valid` | Required values are present and the project configuration loaded successfully. |
| `synchronization preflight: passed` | The configured Mutagen session flushed successfully before the probe. |
| `source freshness: not verified` | No synchronization preflight is configured. Confirm a shared checkout or completed external sync before testing. |
| `authoritative execution: ready` | The configured destination accepted a non-interactive command in `DEV_EXEC_DIR` using the selected shell. |

The trusted `.dev-exec.env` declares which environment is authoritative. Doctor verifies that the wrapper reaches that declaration; it cannot independently decide that a different endpoint should be authoritative. Its exit status reflects configuration, synchronization, and delegated-execution failures. A missing synchronization preflight is reported in output but is not itself non-zero because a genuinely shared checkout needs no flush.

Use `dev-exec doctor --verbose` only for user-approved troubleshooting. Underlying synchronization or connection tools may print hosts, users, paths, operating-system details, or other infrastructure values.

## Source Freshness and Ownership

`dev-exec` cannot infer whether an unconfigured remote checkout contains the current local edits.

- With `DEV_EXEC_MUTAGEN_SESSION`, the wrapper flushes the named session before SSH.
- Without it, confirm that `DEV_EXEC_DIR` is the same shared checkout or that another synchronization mechanism has completed before accepting remote results.
- Stop when freshness is unknown.

Prefer non-mutating validation commands. Before running installs, formatters, code generators, snapshot updates, migrations, or any command that can modify repository files, decide which checkout owns those changes and how they will return to the AI editing environment. Do not leave authoritative source changes stranded remotely.

## Mutagen Preflight

When `DEV_EXEC_MUTAGEN_SESSION` is non-empty, the wrapper runs:

```sh
mutagen sync flush -- SESSION
```

It waits for completion before opening SSH. A non-zero flush status is returned immediately, so a command is never run against a knowingly stale authoritative copy.

The flush runs in the same environment as `dev-exec`. If Claude or Codex runs in
a VM, install Mutagen there and create the session there (or expose the session
through the approved user environment). Installing Mutagen only on the
authoritative Mac does not satisfy this preflight.

## Troubleshooting

- **Configuration not found:** Run from inside the intended project tree, or export the required variables explicitly.
- **SSH cannot connect:** Test the exact `DEV_EXEC_HOST` alias with the system SSH client and inspect `~/.ssh/config`.
- **Remote directory fails:** Confirm `DEV_EXEC_DIR` is absolute and exists on the authoritative machine.
- **Shell fails:** Set `DEV_EXEC_SHELL` to an executable available on the authoritative machine.
- **Mutagen fails:** Resolve the session state and rerun. Do not bypass the flush to force validation.
