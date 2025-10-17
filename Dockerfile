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

# Build Session Desktop AppImage entirely inside Debian 13 (trixie, with pyenv & f-string fix)
FROM debian:13-slim AS builder
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash","-o","pipefail","-lc"]

# ---- tweakables ----
ARG SESSION_REPO=https://github.com/session-foundation/session-desktop.git
ARG SESSION_REF=v1.16.10
ARG USER=node
ARG UID=1000
ARG GID=1000
ARG NODE_DEFAULT=20.18.2
ARG ELECTRON_BUILDER_VERSION=24

ENV CI=1 \
  npm_config_fund=false \
  npm_config_audit=false

# ---- system deps ----
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl git git-lfs gnupg build-essential \
  cmake ninja-build pkg-config \
  libx11-dev libxkbfile-dev libsecret-1-dev \
  libgtk-3-0 libnss3 libasound2 \
  fakeroot rpm dpkg xz-utils file \
  make libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libffi-dev liblzma-dev tk-dev wget \
  && rm -rf /var/lib/apt/lists/* \
  && git lfs install --system

# ---- unprivileged user ----
RUN groupadd -g ${GID} ${USER} && useradd -l -m -u ${UID} -g ${GID} ${USER}
USER ${USER}
WORKDIR /home/${USER}

# ---- Node via nvm ----
ENV NVM_DIR=/home/${USER}/.nvm
RUN mkdir -p "$NVM_DIR" && curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# ---- Python 3.12 via pyenv ----
ENV PYENV_ROOT=/home/${USER}/.pyenv
ENV PATH=${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}
RUN curl -fsSL https://pyenv.run | bash && \
  export PYENV_ROOT="$HOME/.pyenv" && \
  export PATH="$PYENV_ROOT/bin:$PATH" && \
  "$PYENV_ROOT/bin/pyenv" install -s 3.12.5 && \
  "$PYENV_ROOT/bin/pyenv" global 3.12.5 && \
  eval "$("$PYENV_ROOT/bin/pyenv" init -)" && \
  python3 --version

# ---- fetch source (pinned tag) ----
RUN git clone --depth=1 --branch "${SESSION_REF}" "${SESSION_REPO}" app
WORKDIR /home/${USER}/app

# ---- compat patch ----
RUN python3 - <<'PY'
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
        if (line.startswith(("from ", "import ")) or
            line.startswith("#") or
            line.strip() == "" or
            line.startswith(("#!/", "# -*-"))):
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

# ---- tool versions & install deps ----
RUN if [[ -f .nvmrc ]]; then NODE_VERSION="$(cat .nvmrc)"; else NODE_VERSION="${NODE_DEFAULT}"; fi; \
  source "$NVM_DIR/nvm.sh"; \
  nvm install "$NODE_VERSION"; \
  nvm use "$NODE_VERSION"; \
  corepack enable; \
  yarn config set network-timeout 600000

RUN source "$NVM_DIR/nvm.sh"; \
  corepack enable; \
  if [[ -f yarn.lock ]]; then \
    yarn --version >/dev/null 2>&1; \
    yarn install --immutable || yarn install; \
  else \
    (npm ci || npm install); \
  fi

ENV HUSKY=0
ENV NODE_OPTIONS=--max_old_space_size=4096

# ---- build ----
RUN export PYENV_ROOT="$HOME/.pyenv"; \
  export PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"; \
  eval "$("$PYENV_ROOT/bin/pyenv" init -)"; \
  python3 --version; \
  source "$NVM_DIR/nvm.sh"; corepack enable; \
  yarn run build

# ---- package AppImage ----
ENV ELECTRON_BUILDER_CACHE=/home/${USER}/.cache/electron-builder
RUN source "$NVM_DIR/nvm.sh"; \
  npx "electron-builder@${ELECTRON_BUILDER_VERSION}" --linux AppImage --publish=never \
  --config.extraMetadata.environment=production

# -------- exporter --------
FROM debian:13-slim AS exporter
SHELL ["/bin/bash","-o","pipefail","-lc"]
ARG ARTIFACT_UID=1000
ARG ARTIFACT_GID=1000
RUN groupadd -g ${ARTIFACT_GID} app && useradd -l -m -u ${ARTIFACT_UID} -g ${ARTIFACT_GID} app
USER app
WORKDIR /out
COPY --from=builder --chown=app:app /home/node/app/dist/ /out/
