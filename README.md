# dockerized-session-desktop

Build Session Desktop for Linux (AppImage, DEB, or RPM) inside a clean Docker environment.  
The build runs entirely in a container, and only the finished artifacts are copied to your host system.

## Features

- Debian 13 (Trixie) base image with modern build dependencies  
- Uses Node.js (via NVM) and Python (via pyenv) inside the container  
- Pinned versions of key tools for reproducible builds  
- Supports multiple Linux targets via the `LINUX_TARGETS` build argument  
  (for example: `appImage`, `deb`, `rpm`, or `deb,rpm,appimage`)  
- Uses a pinned version of `electron-builder` for consistent output  
- Includes a helper build script (`build_session-desktop.sh`) that:  
  - Determines the latest Session Desktop release automatically  
  - Builds the Docker image with Docker BuildKit  
  - Exports the resulting artifacts to `./out`  

## Requirements

- Docker installed and accessible by your user  
- Internet access for fetching the Session source and dependencies  

## Quick Start (manual Docker commands)

Build a specific version of Session Desktop:

```bash
docker build --pull \
  --build-arg SESSION_REF=v1.16.10 \
  -t session-desktop-builder .
```

Run the build:

```bash
docker run --rm \
  -e LINUX_TARGETS="appimage" \
  -e GH_TOKEN=skip \
  --name session-temp \
  session-desktop-builder
```

Copy artifacts from the container:

```bash
CID=$(docker create session-desktop-builder)
mkdir -p out
docker cp "$CID:/out/." ./out/
docker rm -f "$CID" >/dev/null
ls -lh out
```

## Quick Start (wrapper script)

The included build script automates the entire process.

Default build (latest stable tag, AppImage target):

```bash
./build_session-desktop.sh
```

Build specific targets:

```bash
LINUX_TARGETS="deb,rpm" ./build_session-desktop.sh
```

Build from a custom branch or repository:

```bash
SESSION_REF=main LINUX_TARGETS="appimage" ./build_session-desktop.sh
```

What it does:

- Determines the latest Session release automatically (via GitHub API)  
- Builds a Docker image using the included Dockerfile  
- Runs the containerized build  
- Copies resulting artifacts to `./out`  
- Cleans up temporary containers and images  

## Configuration

You can override these environment variables:

- `LINUX_TARGETS` — Build targets (`appimage`, `deb`, `rpm`)  
- `SESSION_REF` — Git tag, branch, or commit to build  
- `ARTIFACT_UID` / `ARTIFACT_GID` — Ownership of exported files  
- `NO_CACHE` — Set to 0 to allow Docker cache reuse  
- `PROGRESS` — Build output mode (`auto`, `plain`)  

## Troubleshooting

If you see permission denied errors:  

- Ensure your user is part of the docker group  
- Run `newgrp docker` after adding yourself to the group  
- Rebuild with `sudo` only as a last resort  

If the build fails during pyenv or NVM setup:  

- Check Docker network connectivity  
- Try rebuilding with `--no-cache`  

If electron-builder warns about publishing:  

- Pass `GH_TOKEN=skip` to disable all release uploads  

## License and Credits

This project provides only the Docker-based build environment.  
Session Desktop and all associated code, licenses, and trademarks belong to the Session Foundation.
