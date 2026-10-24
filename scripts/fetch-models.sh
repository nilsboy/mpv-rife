#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RAW_BASE="https://raw.githubusercontent.com/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan/master/models"
# RIFE looks for models under <directory containing librife.so>/models, which is
# where the plugin installs them (PREFIX/lib/vapoursynth/models).
MODELS_DIR="${MODELS_DIR:-$PREFIX/lib/vapoursynth/models}"

# Model id -> directory name, mirroring the mapping in RIFE/plugin.cpp.
declare -A MODEL_DIRS=(
    [0]=rife
    [1]=rife-HD
    [2]=rife-UHD
    [3]=rife-anime
    [4]=rife-v2
    [5]=rife-v2.3
    [6]=rife-v2.4
    [7]=rife-v3.0
    [8]=rife-v3.1
    [9]=rife-v3.9_ensembleFalse_fastTrue
    [10]=rife-v3.9_ensembleTrue_fastFalse
    [11]=rife-v4_ensembleFalse_fastTrue
    [12]=rife-v4_ensembleTrue_fastFalse
    [13]=rife-v4.1_ensembleFalse_fastTrue
    [14]=rife-v4.1_ensembleTrue_fastFalse
    [15]=rife-v4.2_ensembleFalse_fastTrue
    [16]=rife-v4.2_ensembleTrue_fastFalse
    [17]=rife-v4.3_ensembleFalse_fastTrue
    [18]=rife-v4.3_ensembleTrue_fastFalse
    [19]=rife-v4.4_ensembleFalse_fastTrue
    [20]=rife-v4.4_ensembleTrue_fastFalse
    [21]=rife-v4.5_ensembleFalse
    [22]=rife-v4.5_ensembleTrue
    [23]=rife-v4.6_ensembleFalse
    [24]=rife-v4.6_ensembleTrue
    [55]=rife-v4.17_lite_ensembleFalse
)

usage() {
    echo "usage: $0 <model-id> [<model-id> ...]" >&2
    echo "  fetches model weights into $MODELS_DIR" >&2
    echo "  ids: ${!MODEL_DIRS[*]}" >&2
    exit 1
}

[[ $# -ge 1 ]] || usage

sudo mkdir -p "$MODELS_DIR"
for id in "$@"; do
    dir="${MODEL_DIRS[$id]:-}"
    [[ -n "$dir" ]] || { echo "unknown model id: $id" >&2; exit 1; }
    dest="$MODELS_DIR/$dir"
    if [[ -n "$(find "$dest" -name '*.bin' 2>/dev/null | head -1)" ]]; then
        echo "model $id ($dir) already present"
        continue
    fi
    echo "fetching $id -> $dir"
    tmp="$(mktemp -d)"
    for name in $(curl -fsSL "https://api.github.com/repos/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan/contents/models/$dir?ref=master" | grep -o '"name": "[^"]*"' | cut -d'"' -f4); do
        curl -fSL --retry 5 --retry-delay 3 -o "$tmp/$name" "$RAW_BASE/$dir/$name"
    done
    sudo mkdir -p "$dest"
    sudo cp -a "$tmp/." "$dest/"
    rm -rf "$tmp"
done

echo "models installed in $MODELS_DIR"
