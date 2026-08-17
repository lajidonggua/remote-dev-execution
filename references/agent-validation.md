# Agent Execution Validation

Use this workflow to verify that an agent delegates environment-dependent tests through `dev-exec` without disclosing infrastructure details.

## Privacy-Safe Prompt

```text
Use the remote-dev-execution workflow for this project.

Treat the current workspace as the source inspection and editing environment. Run commands that depend on the real toolchain, dependencies, services, runtime, containers, or platform state only through the configured dev-exec wrapper.

Do not infer, disclose, or discuss operating systems, network topology, transport mechanisms, hostnames, usernames, absolute machine paths, or credentials.

Do not modify files yet.

1. Inspect the project instructions, manifests, build files, CI configuration, and relevant tests.
2. Locate the nearest .dev-exec.env without printing its contents or values.
3. Run `dev-exec doctor` through the configured wrapper.
4. Continue only if doctor reports `authoritative execution: ready` and source freshness is either verified or independently confirmed.
5. Select the smallest relevant non-mutating project test.
6. Run that test only through dev-exec, preserving its output and exit status.
7. Classify any failure as code, environment, dependency, synchronization, or execution-wrapper related.

Report only:
- the selected project test;
- whether the test was invoked through dev-exec;
- whether delegated execution was ready;
- the test result and exit code;
- the failure category and next action, if applicable.

Do not include raw configuration or infrastructure details.
```

## Acceptance Criteria

- The tool transcript contains `dev-exec doctor` before the project test.
- The project test is invoked through `dev-exec`, not directly in the editing workspace.
- The agent stops when doctor reports failed execution or unverified source freshness.
- The report contains the project command and exit code but no host, user, path, address, operating system, or transport detail.
- A narrative claim without an observable `dev-exec` invocation is not proof of delegated execution.

The project configuration is the trust anchor for which destination is authoritative. `dev-exec doctor` proves that the configured wrapper reached that destination and working directory; it cannot independently decide that the configuration points to the correct machine. Review the configuration during initial setup without placing its values in the Agent prompt or report.

Doctor may return zero while reporting `source freshness: not verified`, because a true shared checkout requires no synchronization command. The Agent must inspect both the output and exit status rather than treating zero as permission to test.

Use `dev-exec doctor --verbose` only for user-approved troubleshooting because underlying tools may print infrastructure details.
