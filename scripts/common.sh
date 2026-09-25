#!/usr/bin/env bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Building on the workspace is unreliable when it is a network mount, so the
# build tree defaults to a local directory.
BUILD_ROOT="${BUILD_ROOT:-/var/tmp/mpv-rife-build}"
PREFIX="${PREFIX:-/usr/local}"
JOBS="${JOBS:-$(nproc)}"

clone_repo() {
    local url="$1"
    local dir="$2"
    shift 2
    local ref=""
    local args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
        if [[ "${args[i]}" == "--branch" ]]; then
            ref="${args[i + 1]}"
        fi
    done
    if [[ -d "$dir/.git" ]]; then
        git -C "$dir" fetch --depth 1 origin "${ref:-HEAD}"
        git -C "$dir" checkout -q --detach FETCH_HEAD
    else
        mkdir -p "$(dirname "$dir")"
        git clone --depth 1 "$@" "$url" "$dir"
    fi
}

install_tree() {
    local message="$1"
    shift
    if [[ -w "$(dirname "$PREFIX")" ]]; then
        "$@"
    else
        sudo "$@"
    fi
    echo "$message"
}
