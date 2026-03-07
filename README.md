# dockerized-session-desktop

Build Session Desktop for Linux inside a clean Docker environment.

The build runs entirely in a container, and only the finished artifacts are exported to your host system.

## Features

- Debian 13 (Trixie) build environment
- Pinned Node.js tarball installed directly in the container
- Python 3 from Debian packages
- Uses pnpm via Corepack with a pinned version for reproducibility
- Supports Linux packaging targets via the `LINUX_TARGETS` build argument
- Uses `electron-builder` from the repo when available, with a pinned fallback version
- Rewrites SSH-based Git submodule URLs to HTTPS for container-friendly builds
- Uses Docker BuildKit cache mounts for:
  - downloaded Node.js tarballs
  - pnpm store
  - electron-builder downloads
- Includes a helper build script (`build_session-desktop.sh`) that:
  - determines the latest Session Desktop release automatically
  - builds with Docker BuildKit / buildx
  - exports the resulting artifacts directly to `./out`

## Requirements

- Docker installed and accessible by your user
- Docker Buildx available
- Internet access for fetching source code and build dependencies

## Quick Start (wrapper script)

The included build script automates the whole process.

Default build (latest stable tag, AppImage target):

```bash
./build_session-desktop.sh
```

Build specific targets:

```bash
LINUX_TARGETS="AppImage deb rpm" ./build_session-desktop.sh
```

Build a specific ref:

```bash
./build_session-desktop.sh v1.17.12
```

The script:

- determines the latest Session release automatically if no ref is given
- creates or reuses a dedicated buildx builder
- builds the `exporter` stage from the Dockerfile
- exports artifacts directly to `./out` via `--output type=local`
- avoids the old `docker create` / `docker cp` flow

## Quick Start (manual buildx commands)

Build and export artifacts directly to `./out`:

```bash
docker buildx build \
  --pull \
  --target exporter \
  --build-arg SESSION_REF=v1.17.12 \
  --build-arg LINUX_TARGETS="AppImage" \
  --output type=local,dest=./out \
  .
```

List the exported artifacts:

```bash
ls -lh ./out
```

## Configuration

You can override these environment variables when using the wrapper script:

- `OUT_DIR` — destination directory for exported artifacts
- `DOCKERFILE` — alternate Dockerfile path
- `NO_CACHE` — set to `0` to allow cache reuse
- `PROGRESS` — build output mode (`auto`, `plain`)
- `LINUX_TARGETS` — Linux targets passed to `electron-builder`  
  Example: `AppImage`, or `AppImage deb rpm`
- `PNPM_VERSION` — pnpm version prepared via Corepack
- `ARTIFACT_UID` / `ARTIFACT_GID` — ownership of exported files on the host

Build-specific Docker args include:

- `SESSION_REF` — Git tag, branch, or commit to build
- `SESSION_REPO` — alternate repository URL
- `NODE_VERSION` — pinned Node.js version
- `NODE_DISTRO` — Node.js distribution suffix
- `ELECTRON_BUILDER_VERSION` — fallback version if the repo does not provide one

## Notes

- Session submodules are rewritten from SSH to HTTPS during the build so they can be fetched inside the container without SSH setup.
- Packaged artifacts are collected from the build output and exported from a minimal `scratch` exporter stage.
- Current packaging output is expected under `release/`, not `dist/`.

## Troubleshooting

If Docker permission errors occur:

- ensure your user is in the `docker` group
- run `newgrp docker` after changing group membership
- use `sudo` only if you really have to

If dependency installation fails:

- check Docker network connectivity
- try again with `NO_CACHE=1`
- verify BuildKit / buildx is available

If submodule checkout fails:

- confirm outbound HTTPS access to GitHub is available
- rebuild without cache to avoid stale Git metadata

If packaging fails after the main build succeeds:

- inspect the `release/` output shown in the build log
- check whether the requested `LINUX_TARGETS` value matches what the project supports

## License and Credits

This project provides a Docker-based build environment only.

Session Desktop and all associated source code, licenses, and trademarks belong to their respective owners.
