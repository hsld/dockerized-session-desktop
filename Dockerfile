# syntax=docker/dockerfile:1

# dockerized-session-desktop
# Copyright (C) 2025 hsld <62700359+hsld@users.noreply.github.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Contact: https://github.com/hsld/dockerized-session-desktop/issues

# build session desktop appimage entirely inside Debian 13 (trixie)
FROM debian:13-slim AS builder
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-lc"]

# tweakables
ARG SESSION_REPO=https://github.com/session-foundation/session-desktop.git
ARG SESSION_REF=v1.17.12
ARG USER=node
ARG UID=1000
ARG GID=1000

# Pin exact Node version (the repo enforces this via engines.node)
ARG NODE_VERSION=24.12.0
ARG NODE_DISTRO=linux-x64

# package tooling
ARG PNPM_VERSION=10.6.4
ARG ELECTRON_BUILDER_VERSION=26.0.0
ARG LINUX_TARGETS=AppImage

ENV CI=1 \
    HUSKY=0 \
    NODE_OPTIONS=--max_old_space_size=4096 \
    npm_config_fund=false \
    npm_config_audit=false \
    npm_config_update_notifier=false \
    COREPACK_ENABLE_AUTO_PIN=0 \
    USE_HARD_LINKS=false

# helpful cache locations (explicit + avoids surprises)
ENV XDG_CACHE_HOME=/home/${USER}/.cache \
    COREPACK_HOME=/home/${USER}/.cache/node/corepack \
    ELECTRON_BUILDER_CACHE=/home/${USER}/.cache/electron-builder \
    PNPM_STORE_DIR=/home/${USER}/.local/share/pnpm/store

# system deps (+ python3 from apt; no pyenv)
RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    ca-certificates curl git git-lfs gnupg build-essential \
    python3 python3-pip \
    cmake ninja-build pkg-config \
    libx11-dev libxkbfile-dev libsecret-1-dev \
    libgtk-3-0 libnss3 libasound2 \
    fakeroot rpm dpkg xz-utils file \
    wget; \
    rm -rf /var/lib/apt/lists/*; \
    git lfs install --system; \
    python3 --version

# Node.js (pinned exact version from nodejs.org tarball)
# BuildKit improvement: cache the downloaded tarball between builds.
RUN --mount=type=cache,id=session-node-tarball,target=/tmp/node-tarball \
    set -eu; \
    mkdir -p /tmp/node-tarball; \
    cd /tmp/node-tarball; \
    TARBALL="node-v${NODE_VERSION}-${NODE_DISTRO}.tar.xz"; \
    if [[ ! -f "${TARBALL}" ]]; then \
    curl -fL -o "${TARBALL}" \
    "https://nodejs.org/dist/v${NODE_VERSION}/${TARBALL}"; \
    fi; \
    rm -rf "node-v${NODE_VERSION}-${NODE_DISTRO}"; \
    tar -xJf "${TARBALL}"; \
    cp -a "node-v${NODE_VERSION}-${NODE_DISTRO}/." /usr/local/; \
    node --version; \
    npm --version

# corepack pnpm (deterministic)
# NOTE: corepack creates shims in /usr/local/bin, so run as root here.
RUN set -eu; \
    corepack enable; \
    corepack prepare "pnpm@${PNPM_VERSION}" --activate; \
    pnpm --version

# unprivileged user
RUN set -eu; \
    groupadd -g "${GID}" "${USER}"; \
    useradd -l -m -u "${UID}" -g "${GID}" "${USER}"; \
    # IMPORTANT: ensure the home directory is owned by the unprivileged user
    chown -R "${UID}:${GID}" "/home/${USER}"

USER ${USER}
WORKDIR /home/${USER}

# ensure cache roots exist and are writable by the unprivileged user
RUN set -eu; \
    mkdir -p \
    "${COREPACK_HOME}" \
    "${ELECTRON_BUILDER_CACHE}" \
    "${PNPM_STORE_DIR}"

# fetch source (pinned tag)
# IMPORTANT: bring submodules. One submodule is configured as SSH; rewrite to
# HTTPS for container builds.
RUN set -eu; \
    git config --global --add url."https://github.com/".insteadOf "git@github.com:"; \
    git config --global --add url."https://github.com/".insteadOf "ssh://git@github.com/"; \
    git clone --depth=1 --branch "${SESSION_REF}" "${SESSION_REPO}" app; \
    cd app; \
    if [[ -f .gitmodules ]]; then \
    sed -i 's|git@github.com:|https://github.com/|g' .gitmodules; \
    sed -i 's|ssh://git@github.com/|https://github.com/|g' .gitmodules; \
    fi; \
    git submodule sync --recursive; \
    git -c protocol.file.allow=always submodule update --init --recursive --depth=1; \
    git lfs pull || true

WORKDIR /home/${USER}/app

# compat patch
RUN set -eu; \
    python3 - <<'PY'
from pathlib import Path
import re

p = Path("tools/localization/localeTypes.py")
if not p.exists():
    print("Patch note: localeTypes.py not present; skipping.")
    raise SystemExit(0)

s = p.read_text()
if "SEP_NL" not in s or "SEP_COMMA_NL" not in s:
    lines = s.splitlines()
    insert_at = 0
    for i, line in enumerate(lines[:120]):
        if (
            line.startswith(("from ", "import "))
            or line.startswith("#")
            or line.strip() == ""
            or line.startswith(("#!/", "# -*-"))
        ):
            insert_at = i + 1
            continue
        break
    inject = []
    if "SEP_NL" not in s:
        inject.append('SEP_NL = "\\n"')
    if "SEP_COMMA_NL" not in s:
        inject.append('SEP_COMMA_NL = ",\\n      "')
    lines[insert_at:insert_at] = inject
    s = "\n".join(lines)
s = re.sub(r'\{\s*["\']\\n["\']\.join\((.*?)\)\s*\}', r'{SEP_NL.join(\1)}', s)
p.write_text(s)
print("localeTypes.py patched: constants ensured + joins normalized")
PY

# install deps (pnpm)
# BuildKit improvement: cache pnpm store between builds (writable by uid/gid)
RUN --mount=type=cache,id=session-pnpm-store,target=/home/${USER}/.local/share/pnpm/store,uid=${UID},gid=${GID},mode=0775 \
    set -eu; \
    pnpm config set store-dir "${PNPM_STORE_DIR}"; \
    pnpm install --frozen-lockfile

# build
RUN set -eu; \
    pnpm run build

# package AppImage (electron-builder)
# BuildKit improvement: cache electron-builder downloads between builds
# (writable by uid/gid)
RUN --mount=type=cache,id=session-electron-builder-cache,target=/home/${USER}/.cache/electron-builder,uid=${UID},gid=${GID},mode=0775 \
    set -eu; \
    rm -rf dist release; \
    mkdir -p "${ELECTRON_BUILDER_CACHE}"; \
    if pnpm exec electron-builder --version >/dev/null 2>&1; then \
    USE_HARD_LINKS=false ELECTRON_BUILDER_PUBLISH=never CI=false \
    pnpm exec electron-builder \
    --linux "${LINUX_TARGETS}" --publish=never \
    --config.extraMetadata.environment=production; \
    else \
    USE_HARD_LINKS=false ELECTRON_BUILDER_PUBLISH=never CI=false \
    pnpm dlx "electron-builder@${ELECTRON_BUILDER_VERSION}" \
    --linux "${LINUX_TARGETS}" --publish=never \
    --config.extraMetadata.environment=production; \
    fi; \
    if [[ ! -d release ]]; then \
    echo "ERROR: packaging completed but no release/ directory was created"; \
    echo "Repository contents after packaging:"; \
    find . -maxdepth 3 \( -type d -o -type f \) | sort | sed -n '1,300p'; \
    exit 1; \
    fi; \
    echo "Packaged files:"; \
    find release -maxdepth 3 -type f | sort

# collect artifacts so exporter does not fail on optional files
RUN set -eu; \
    mkdir -p /home/${USER}/export; \
    if [[ -d release ]]; then \
    find release -maxdepth 3 -type f \
    \( -name '*.AppImage' -o -name '*.AppImage.zsync' -o -name '*.blockmap' \) \
    -exec cp -t /home/${USER}/export {} +; \
    fi; \
    echo "Exported artifacts:"; \
    ls -la /home/${USER}/export; \
    test -n "$(find /home/${USER}/export -maxdepth 1 -type f -name '*.AppImage' -print -quit)"

# exporter (artifacts only; buildx local output should contain only these files)
FROM scratch AS exporter
ARG ARTIFACT_UID=1000
ARG ARTIFACT_GID=1000

# export only the AppImage (+ common companion files)
COPY --from=builder --chown=${ARTIFACT_UID}:${ARTIFACT_GID} /home/node/export/ /
