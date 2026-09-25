#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$BUILD_ROOT/rife"
NCNN_SRC="$SRC/subprojects/ncnn"

# RIFE is small but ships hundreds of MB of model weights in its history, so
# fetch source only.
if [[ ! -d "$SRC/.git" ]]; then
    git clone --filter=blob:none --no-checkout --depth 1 \
        https://github.com/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan.git "$SRC"
    git -C "$SRC" sparse-checkout init --cone
    git -C "$SRC" sparse-checkout set RIFE pkgconfig subprojects
    git -C "$SRC" checkout
fi

# ncnn and its glslang fork are pinned by gitlink; use exactly those revisions.
NCNN_REV="$(git -C "$SRC" ls-tree HEAD subprojects/ncnn | awk '{print $3}')"
if [[ ! -d "$NCNN_SRC/.git" ]]; then
    clone_repo https://github.com/Tencent/ncnn.git "$NCNN_SRC"
fi
git -C "$NCNN_SRC" fetch --depth 1 origin "$NCNN_REV"
git -C "$NCNN_SRC" checkout "$NCNN_REV"

GLSLANG_REV="$(git -C "$NCNN_SRC" ls-tree HEAD glslang | awk '{print $3}')"
if [[ ! -d "$NCNN_SRC/glslang/.git" ]]; then
    rm -rf "$NCNN_SRC/glslang"
    clone_repo https://github.com/nihui/glslang.git "$NCNN_SRC/glslang"
fi
git -C "$NCNN_SRC/glslang" fetch --depth 1 origin "$GLSLANG_REV"
git -C "$NCNN_SRC/glslang" checkout "$GLSLANG_REV"

meson setup "$SRC/build" "$SRC" \
    --prefix="$PREFIX" \
    --buildtype=release
ninja -C "$SRC/build" -j "$JOBS"
install_tree "RIFE plugin installed" \
    ninja -C "$SRC/build" install

VS_PKG="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')/vapoursynth"
echo "RIFE plugin installed to $VS_PKG"
ls "$VS_PKG"/*rife* "$VS_PKG"/models 2>/dev/null || true
