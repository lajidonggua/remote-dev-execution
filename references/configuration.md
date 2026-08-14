# Configuration

Use a project-local `.dev-exec.env` to describe the authoritative development environment without placing machine-specific values in this Skill repository.

## Lookup and Precedence

`dev-exec` starts at the caller's current directory and searches each parent directory for the nearest `.dev-exec.env`. This lets commands run from nested package or test directories.

For a relay-managed VM, the Mac setup command can generate the project file after the paths are confirmed:

```sh
~/code/remote-dev-execution/scripts/dev-relay setup VM_ALIAS \
  --project /absolute/path/to/project/on/the/vm \
           /absolute/path/to/project/on/the/mac \
  --shell /bin/zsh \
  --mutagen SESSION
```

Both paths are required because their relationship is project-specific. The generated file is marked as managed, written with mode `0600`, replaced atomically on repeat setup, and refused when an unmarked file or symlink already exists. When the VM project is a Git checkout, setup adds `.dev-exec.env` to `.git/info/exclude` when that local file is writable. It never adds the project-specific path to this Skill repository.

The file is optional when all required values are already exported in the process environment. Explicit process environment values take precedence over values loaded from the file, which supports temporary overrides:

```sh
DEV_EXEC_SHELL=/bin/zsh dev-exec -- npm test
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

## Troubleshooting

- **Configuration not found:** Run from inside the intended project tree, or export the required variables explicitly.
- **SSH cannot connect:** Test the exact `DEV_EXEC_HOST` alias with the system SSH client and inspect `~/.ssh/config`.
- **Remote directory fails:** Confirm `DEV_EXEC_DIR` is absolute and exists on the authoritative machine.
- **Shell fails:** Set `DEV_EXEC_SHELL` to an executable available on the authoritative machine.
- **Mutagen fails:** Resolve the session state and rerun. Do not bypass the flush to force validation.
