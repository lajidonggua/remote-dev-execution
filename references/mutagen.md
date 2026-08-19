# Mutagen Synchronization

Use Mutagen when the AI editing environment and authoritative development
environment have separate project checkouts. It keeps Agent file operations on
the Agent's local filesystem while making current edits available for delegated
builds, tests, and debugging.

## Contents

- [Choose Mutagen or a shared checkout](#choose-mutagen-or-a-shared-checkout)
- [Where Mutagen runs](#where-mutagen-runs)
- [Recommended project setup](#recommended-project-setup)
- [Install without administrator access](#install-without-administrator-access)
- [Configure an existing session](#configure-an-existing-session)
- [Choose ignores](#choose-ignores)
- [Doctor and execution checks](#doctor-and-execution-checks)
- [Operate and repair a session](#operate-and-repair-a-session)
- [Ownership and security](#ownership-and-security)

## Choose Mutagen or a shared checkout

| Checkout relationship | Recommendation |
| --- | --- |
| Both environments access the same underlying files through a reliable local mount | Do not add Mutagen. Leave `DEV_EXEC_MUTAGEN_SESSION` unset and document the reviewed shared-checkout guarantee. |
| Each environment has its own checkout | Prefer Mutagen unless the team already has another synchronization mechanism with a blocking completion check. |
| The project is mounted over a high-latency network filesystem | Prefer separate local checkouts plus Mutagen for Agent-heavy scans and edits. |
| The current environment is already authoritative | Do not use this Skill or Mutagen for delegated execution. |

Mutagen synchronizes two checkouts. It is not the SSH transport used by
`dev-exec`, and it is not a shared checkout.

## Where Mutagen runs

There are two supported control modes:

1. **Agent-local (recommended for a new session):** install Mutagen and create
   the session in the environment where `dev-exec` runs. This is what
   `setup-mutagen.sh` configures.
2. **Explicit remote control:** keep an existing session in another approved
   environment and set both `DEV_EXEC_MUTAGEN_SESSION` and
   `DEV_EXEC_MUTAGEN_HOST`. The wrapper runs the Mutagen CLI on that SSH alias
   for `version`, `sync list`, and `sync flush`, then applies the same health
   gate before delegated execution.

Installing Mutagen only in another environment without
`DEV_EXEC_MUTAGEN_HOST` does not satisfy the preflight. The control host must be
reachable non-interactively from the Agent environment and must be the owner
of the named session.

The session uses:

- the directory containing the nearest `.dev-exec.env` as the editing
  endpoint; and
- `DEV_EXEC_HOST` plus `DEV_EXEC_DIR` as the authoritative endpoint.

The SSH alias used by `DEV_EXEC_HOST` must already work non-interactively from
the Agent environment. With `dev-relay`, run relay setup before creating the
Mutagen session so the generated alias and project configuration exist.

## Recommended project setup

First create `.dev-exec.env` manually or with `dev-relay setup --project`.
When no session exists yet, omit `--mutagen` from that first relay setup.

Then run this inside the Agent project:

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
```

Add only project-specific generated directories that should not cross the
environment boundary:

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync \
  --ignore node_modules \
  --ignore build
```

Use only ignores appropriate for the project. The helper:

1. Finds the nearest `.dev-exec.env`.
2. Optionally installs the pinned Mutagen release into `~/.local/bin`.
3. Derives both endpoints from the existing project configuration.
4. Creates a named `two-way-safe` session.
5. Always ignores VCS metadata and `.dev-exec.env`.
6. Refuses a tracked `.dev-exec.env` and adds an untracked one to the
   repository's local `.git/info/exclude` when applicable.
7. Performs an initial flush.
8. Atomically adds `DEV_EXEC_MUTAGEN_SESSION` and, when required,
   `DEV_EXEC_MUTAGEN_BIN` to the project configuration.
9. Runs the redacted `dev-exec doctor` check.

The helper refuses to rewrite an existing Mutagen assignment, apply new
`--ignore` values to an already configured session, replace a symlinked config,
or reuse an ambiguous session name. It removes a new session
when creation, initial flush, or config installation fails. A later
authoritative-execution failure leaves the healthy session configured so the
connection can be repaired without recreating synchronization. Run with
`--verbose` only when the user accepts endpoint and path details in diagnostic
output.

If `--name` is omitted, the helper derives a stable local name from the project
directory and config path. An explicit team naming convention is easier to
operate and is recommended.

## Install without administrator access

The convenient setup command above installs Mutagen only when it is not
already available. To install it separately:

```sh
~/code/remote-dev-execution/scripts/install-mutagen.sh
~/.local/bin/mutagen version
```

The installer supports macOS and Linux on amd64 and arm64. It downloads a
pinned official release, verifies the archive against that release's
`SHA256SUMS`, and installs only the `mutagen` executable. It never invokes
`sudo`. It requires `curl` or `wget`, `tar`, and either `sha256sum` or
`shasum`.

Select a reviewed version explicitly when the team updates its pin:

```sh
~/code/remote-dev-execution/scripts/install-mutagen.sh \
  --version REVIEWED_VERSION \
  --force
```

On a machine where Homebrew is already approved, this is also valid:

```sh
brew install mutagen-io/mutagen/mutagen
```

For stricter supply-chain policy, verify the official `SHA256SUMS.gpg`
signature independently before approving a new version. A checksum manifest
downloaded from the same release protects integrity but is not an independent
publisher-authentication channel.

## Configure an existing session

When the session already exists where `dev-exec` runs, do not create another
one. Add its exact name during relay project setup:

```sh
dev-relay setup VM_ALIAS \
  --project AGENT_PROJECT_DIR AUTHORITATIVE_PROJECT_DIR \
  --mutagen EXISTING_SESSION \
  --mutagen-host MUTAGEN_CONTROL_HOST
```

Or add these assignments to the ignored project configuration:

```sh
DEV_EXEC_MUTAGEN_SESSION=project-sync
DEV_EXEC_MUTAGEN_BIN=mutagen
# Only when the session is controlled in another environment.
# DEV_EXEC_MUTAGEN_HOST=sync-control
```

`DEV_EXEC_MUTAGEN_BIN` may be an executable name on `PATH` or an absolute path
in the selected control environment. Confirm the existing session before
testing. For a remote control host, run these commands there (or use
`dev-exec doctor` after configuration):

```sh
mutagen sync list -- project-sync
mutagen sync flush -- project-sync
dev-exec doctor
```

## Choose ignores

The setup helper always enables `--ignore-vcs` and ignores
`.dev-exec.env`. Pass additional ignores for large, reproducible,
environment-specific outputs, for example:

- dependency caches such as `node_modules` or `.venv`;
- compiler outputs such as `build`, `dist`, or `target`; and
- tool caches that are recreated independently in each environment.

Do not copy this list blindly. Do not ignore source, migrations, lockfiles,
fixtures, generated artifacts that are reviewed, or any file required by the
authoritative command. Review project manifests and CI behavior first.

An ignore means changes under that path never reach the other checkout. The
authoritative environment must provision its own ignored dependencies and
tool outputs.

## Doctor and execution checks

For a configured session, every `dev-exec` command performs this blocking
preflight before opening SSH:

1. Run `mutagen sync flush -- SESSION` and wait for the cycle, locally or on
   `DEV_EXEC_MUTAGEN_HOST` when configured.
2. Query structured session state with a fixed-token template.
3. Reject disconnected endpoints, conflicts, last-session errors, scan
   problems, and transition problems.

Mutagen can complete a flush while preserving `two-way-safe` conflicts, so a
zero flush status alone is not sufficient. The structured health query emits
only a fixed category and never prints conflict paths in default output.

`dev-exec doctor` adds separate checks for executable availability and session
visibility. Healthy output includes:

```text
dev-exec doctor: configuration: valid
dev-exec doctor: synchronization tool: available
dev-exec doctor: synchronization session: available
dev-exec doctor: synchronization health: healthy
dev-exec doctor: synchronization preflight: passed
dev-exec doctor: authoritative execution: ready
```

The wrapper never starts the delegated command when any synchronization check
fails. Use `doctor --verbose` only for user-approved troubleshooting because
Mutagen may print endpoint paths and transport details.

## Operate and repair a session

Use Mutagen directly for user-approved maintenance:

```sh
mutagen sync list --long -- project-sync
mutagen sync flush -- project-sync
mutagen sync pause -- project-sync
mutagen sync resume -- project-sync
```

When `DEV_EXEC_MUTAGEN_HOST` is set, run the same maintenance commands on the
configured control host, or invoke them through its approved SSH alias. Do not
start a second session with the same checkout pair from another Mutagen daemon.

The Mutagen daemon starts on demand and persists session definitions. After a
restart or network interruption, run `dev-exec doctor`; it will force a cycle
and stop before delegated execution if the session cannot recover.

For conflicts, inspect `mutagen sync list --long` as the user, decide which
content is correct, reconcile the files in the owning checkout, then rerun
doctor. Do not make the Agent bypass the health gate.

Terminate a session only when intentionally removing or recreating its
configuration:

```sh
mutagen sync terminate -- project-sync
```

Remove or replace `DEV_EXEC_MUTAGEN_SESSION` at the same time so future
commands do not reference a deleted session.

## Ownership and security

- Keep `.dev-exec.env` ignored and out of Git.
- Keep credentials in SSH configuration and key storage, not in Mutagen or
  project config values.
- Use `two-way-safe`; do not switch to a resolved mode that can silently choose
  one side without an explicit team policy.
- Decide which checkout owns formatter, generator, migration, snapshot, and
  install outputs before running mutating commands.
- Never accept a test result after an unverified or unhealthy preflight.
