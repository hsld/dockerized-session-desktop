# Security Policy

This repository provides a Docker-based **build environment** for producing Session Desktop Linux artifacts (AppImage/DEB/RPM) in a clean container, exporting only the resulting build outputs to the host.

It does **not** ship or maintain Session Desktop itself. Security issues in Session Desktop should be reported upstream to the Session Foundation / Session Desktop project.

## Supported Versions

Only the **latest commit on the default branch** is considered supported for security-related fixes in this repository.

Older commits, forks, and locally modified versions are not maintained.

## Reporting a Vulnerability

### Please do **not** disclose sensitive details in public issues

If the report involves any of the following, treat it as sensitive:

- credentials or tokens (e.g., `GH_TOKEN`)
- supply-chain concerns (malicious dependency downloads, tampered artifacts)
- host escape or privilege escalation from the container
- arbitrary file write outside `./out` / path traversal issues
- anything that could realistically be weaponized

### Preferred reporting channel: GitHub private vulnerability reporting

Use GitHub’s private vulnerability reporting if available:

1. Go to the repository page on GitHub
2. Open **Security → Advisories**
3. Click **Report a vulnerability**

If you cannot use private reporting, open an issue with **minimal** information (no exploit code, no secrets) and state that you can share full details privately.

### What to include

- Affected file(s) and a short description of the problem
- Steps to reproduce (as safely as possible)
- Expected vs. actual behavior
- Impact assessment (what an attacker could do)
- Any mitigations or fixes you’ve tested

## Scope

### In scope

- Dockerfile(s), build scripts, and wrapper scripts (e.g., `build_session-desktop.sh`)
- Any code that fetches sources, dependencies, or releases (e.g., “latest release” logic)
- Artifact export logic (permissions/ownership, path handling)
- Hardening settings and container runtime flags described in documentation

### Out of scope

- Vulnerabilities in Session Desktop itself or its upstream dependencies (report upstream as well)
- Misuse of the template in downstream environments
- Issues that require intentionally unsafe Docker settings (e.g., `--privileged`) unless the repo recommends them

## Handling and Disclosure

- Best effort will be made to acknowledge reports, but **no response time or fix timeline is guaranteed**.
- Fixes will typically be delivered via commits to the default branch.
- If a coordinated disclosure date is needed, propose one in your report.

## Operational Security Notes (for users)

- Treat `GH_TOKEN` as a secret. Do not commit it or paste it into logs/issues.
- Prefer building from pinned tags/refs when reproducibility matters.
- Review the build container’s network access and any downloaded tooling if using this in high-assurance environments.
- Scan produced artifacts before distribution if you use this in automated pipelines.
