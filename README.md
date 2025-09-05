# dockerized-session-desktop

Build a **Session Desktop** AppImage entirely inside Docker. The host stays clean; only the final artifacts are copied out.

## Features

- **Hermetic build** on Debian 12 (`debian:12-slim`).
- **Node via nvm** (respects repo `.nvmrc`, with safe fallback).
- **Python 3.12 via pyenv** for the localization tools.
- **Auto-patch** for a known f-string issue in `tools/localization/localeTypes.py` on the 1.16.x line.
- **Stable packaging** with `electron-builder@24` and `--publish=never`.
- **Non-root artifacts**: builds as an unprivileged user.
- **One-command helper script** (`build_session-desktop.sh`) that does the Docker build **and** copies artifacts out for you.

## Prerequisites

- Docker (BuildKit recommended)

## Quick start (Docker CLI)

~~~bash
# Build the image (pinned to a stable tag by default)
docker build --pull \
  --build-arg SESSION_REF=v1.16.7 \
  -t session-desktop-builder .

# Copy artifacts out of the image
CID="$(docker create session-desktop-builder)"
mkdir -p out
docker cp "$CID:/out/." ./out/
docker rm -f "$CID" >/dev/null

# Inspect results
ls -lh out
~~~

You should see something like:

~~~
session-desktop-linux-x86_64-1.16.7.AppImage
latest-linux.yml
builder-debug.yml
linux-unpacked/
~~~

## Quick start (wrapper script)

Prefer a single command that builds **and** copies out artifacts? Use the helper script:

~~~bash
# run the wrapper (auto-picks latest release unless you pass a tag)
./build_session-desktop.sh

# or pin a specific tag:
./build_session-desktop.sh v1.16.7

# optional envs
OUT_DIR=out       \   # where to place artifacts (default: ./out)
NO_CACHE=0        \   # allow Docker cache (default: 1 = no-cache)
DOCKERFILE=./Dockerfile \
./build_session-desktop.sh
~~~

What it does:

- Determines the tag (CLI arg > $SESSION_REF env > GitHub latest > git tag fallback).
- Builds the Docker image with that tag.
- Creates an ephemeral container and **copies `/out` to `./out/`**.
- Cleans up the container and image.

## Build args

| Arg            | Default                                                     | Notes                                      |
|----------------|-------------------------------------------------------------|--------------------------------------------|
| `SESSION_REPO` | `https://github.com/session-foundation/session-desktop.git` | Upstream repo                              |
| `SESSION_REF`  | `v1.16.7`                                                   | Tag/branch to build                        |
| `NODE_DEFAULT` | `20.18.2`                                                   | Used only if repo lacks `.nvmrc`           |
| `UID`/`GID`    | `1000`/`1000`                                               | Owner of files created in the container    |

Example:

~~~bash
docker build -t session-desktop:mytag \
  --build-arg SESSION_REF=v1.16.8 \
  --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" .
~~~

## How it works

- Base image installs toolchains & Electron runtime libs.
- Adds a non-root user.
- Installs **Node (nvm)** and **Python 3.12 (pyenv)**.
- Clones Session at `SESSION_REF`.
- Patches `localeTypes.py` (adds constants & replaces `"\n".join(...)`).
- `yarn install` + `yarn run build`.
- Packages via `npx electron-builder@24 --linux AppImage --publish=never`.
- Final stage exports `/home/node/app/dist` to `/out`.

## Tips

- Use a `.dockerignore` to keep contexts small:

  ~~~
  node_modules
  dist
  out
  .git
  *.AppImage
  ~~~

- Cache electron-builder downloads:

  ~~~dockerfile
  ENV ELECTRON_BUILDER_CACHE=/home/node/.cache/electron-builder
  ~~~

## License & Credits

This repo only provides a Dockerized build wrapper for **Session Desktop**. All code, licenses, and trademarks for Session belong to their respective owners.
