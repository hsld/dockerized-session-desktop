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

set -euo pipefail

# ----------------------------- config ---------------------------------
REPO_SLUG="session-foundation/session-desktop"
IMAGE_BASENAME="session-desktop-builder"
OUT_DIR="${OUT_DIR:-out}"              # override: OUT_DIR=/some/path ./build_session-desktop.sh
DOCKERFILE="${DOCKERFILE:-Dockerfile}" # override if needed
NO_CACHE="${NO_CACHE:-1}"              # set to 0 to allow cache
# ----------------------------------------------------------------------

say() { printf "\033[1;36m>> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m!! %s\033[0m\n" "$*"; }
die() {
    printf "\033[1;31mXX %s\033[0m\n" "$*"
    exit 1
}

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
need docker
need curl

latest_tag_from_api() {
    # Try GitHub API with jq (if present), else minimal grep/sed
    local tag=""
    if command -v jq >/dev/null 2>&1; then
        tag="$(curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/releases/latest" | jq -r .tag_name 2>/dev/null || true)"
    else
        tag="$(curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/releases/latest" |
            grep -m1 -Eo '"tag_name"\s*:\s*"[^"]+"' |
            sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/' || true)"
    fi
    printf "%s" "${tag}"
}

latest_tag_from_refs() {
    # Fallback without API rate limits (requires git)
    if ! command -v git >/dev/null 2>&1; then
        printf ""
        return 0
    fi
    git ls-remote --tags "https://github.com/${REPO_SLUG}.git" |
        awk -F/ '/refs\/tags\/v?[0-9]/{print $3}' |
        sed 's/\^{}//' |
        sort -V |
        tail -1
}

pick_tag() {
    # 1) user override via CLI arg; 2) env SESSION_REF; 3) API; 4) refs fallback
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

copy_out() {
    local cid="$1"
    local src="/out"
    local dst="${OUT_DIR}"
    mkdir -p "${dst}"
    say "Exporting AppImage artifact(s) only…"
    docker cp "${cid}:${src}/." "${dst}/"
    # show a quick listing
    (
        set +e
        echo ">> Done. Artifacts in: ${dst}"
        ls -lh "${dst}"
    )
}

clean_objects() {
    local cid="$1" img="$2"
    (
        set +e
        [[ -n "${cid}" ]] && docker rm -f "${cid}" >/dev/null 2>&1
        [[ -n "${img}" ]] && docker rmi -f "${img}" >/dev/null 2>&1
    )
}

main() {
    local want_tag
    want_tag="$(pick_tag "${1:-}")"
    say "Building Session Desktop @ ${want_tag}"

    enable_buildkit

    [[ -f "${DOCKERFILE}" ]] || die "Dockerfile not found at: ${DOCKERFILE}"

    local build_args=(--pull --file "${DOCKERFILE}" --build-arg "SESSION_REF=${want_tag}")
    if [[ "${NO_CACHE}" == "1" ]]; then
        build_args+=(--no-cache)
    fi

    local image_tag="${IMAGE_BASENAME}:${want_tag}"
    say "Docker build → ${image_tag}"
    docker build "${build_args[@]}" -t "${image_tag}" .

    say "Creating ephemeral container to copy artifacts…"
    local cid=""
    cid="$(docker create "${image_tag}")"

    # Always clean up container & image on exit
    trap 'clean_objects "${cid}" "'${image_tag}'"' EXIT

    copy_out "${cid}"

    say "Removing the build image to keep Docker tidy…"
    clean_objects "${cid}" "${image_tag}"
    trap - EXIT
}

main "$@"
