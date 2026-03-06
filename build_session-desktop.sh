#!/usr/bin/env bash

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

# Exit immediately if any command fails
# Treat unset variables as errors
# Ensure the whole pipeline fails if any one command in it fails
set -euo pipefail

# ----------------------------- config ---------------------------------
REPO_SLUG="session-foundation/session-desktop"
IMAGE_BASENAME="${IMAGE_BASENAME:-session-desktop-builder}"
OUT_DIR="${OUT_DIR:-out}" \
    # override: OUT_DIR=/some/path ./build_session-desktop.sh
DOCKERFILE="${DOCKERFILE:-Dockerfile}" \
    # override if needed
NO_CACHE="${NO_CACHE:-1}" \
    # set to 0 to allow cache
PROGRESS="${PROGRESS:-auto}" \
    # auto|plain

# Session build args you can override
LINUX_TARGETS="${LINUX_TARGETS:-AppImage}" # e.g. "AppImage deb rpm"
PNPM_VERSION="${PNPM_VERSION:-10.6.4}"
ARTIFACT_UID="${ARTIFACT_UID:-1000}"
ARTIFACT_GID="${ARTIFACT_GID:-1000}"
# ----------------------------------------------------------------------

say() { printf "\033[1;36m>> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m!! %s\033[0m\n" "$*"; }
die() { printf "\033[1;31mXX %s\033[0m\n" "$*"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
need docker
need curl
need git

ensure_builder() {
    if ! docker buildx inspect sesd >/dev/null 2>&1; then
        say "Creating buildx builder 'sesd' (docker-container)…"
        docker buildx create --name sesd --driver docker-container --use \
            >/dev/null
    else
        docker buildx use sesd >/dev/null
    fi
    docker buildx inspect --bootstrap >/dev/null
}

latest_tag_from_api() {
    local tag=""
    if command -v jq >/dev/null 2>&1; then
        tag="$(
            curl -fsSL \
                "https://api.github.com/repos/${REPO_SLUG}/releases/latest" |
                jq -r .tag_name 2>/dev/null || true
        )"
    else
        tag="$(
            curl -fsSL \
                "https://api.github.com/repos/${REPO_SLUG}/releases/latest" |
                grep -m1 -Eo '"tag_name"\s*:\s*"[^"]+"' |
                sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/' || true
        )"
    fi
    printf "%s" "${tag}"
}

latest_tag_from_refs() {
    git ls-remote --tags "https://github.com/${REPO_SLUG}.git" |
        awk -F/ '/refs\/tags\/v?[0-9]/{print $3}' |
        sed 's/\^{}//' |
        sort -V |
        tail -1
}

pick_tag() {
    local arg_tag="${1:-}"
    if [[ -n "${arg_tag}" ]]; then
        printf "%s" "${arg_tag}"
        return
    fi
    if [[ -n "${SESSION_REF:-}" ]]; then
        printf "%s" "${SESSION_REF}"
        return
    fi
    local t=""
    t="$(latest_tag_from_api)"
    if [[ -z "${t}" ]]; then
        warn "GitHub API lookup failed or empty; trying refs…"
        t="$(latest_tag_from_refs)"
    fi
    [[ -n "${t}" ]] || die "Could not determine latest release tag."
    printf "%s" "${t}"
}

enable_buildkit() {
    export DOCKER_BUILDKIT=1
    export COMPOSE_DOCKER_CLI_BUILD=1
}

main() {
    local want_tag
    want_tag="$(pick_tag "${1:-}")"
    say "Building Session Desktop @ ${want_tag}"

    enable_buildkit
    [[ -f "${DOCKERFILE}" ]] || die "Dockerfile not found at: ${DOCKERFILE}"

    ensure_builder

    local build_args=(
        --pull
        --file "${DOCKERFILE}"
        --progress "${PROGRESS}"
        --target exporter
        --build-arg "SESSION_REF=${want_tag}"
        --build-arg "LINUX_TARGETS=${LINUX_TARGETS}"
        --build-arg "PNPM_VERSION=${PNPM_VERSION}"
        --build-arg "ARTIFACT_UID=${ARTIFACT_UID}"
        --build-arg "ARTIFACT_GID=${ARTIFACT_GID}"
    )
    if [[ "${NO_CACHE}" == "1" ]]; then
        build_args+=(--no-cache)
    fi

    say "Exporting artifacts directly to: ${OUT_DIR}"
    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"

    docker buildx build "${build_args[@]}" \
        --output "type=local,dest=${OUT_DIR}" \
        .

    say ">> Done. Artifacts in: ${OUT_DIR}"
    ls -lh "${OUT_DIR}" || true
}

main "$@"
