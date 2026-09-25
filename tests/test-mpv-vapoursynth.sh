#!/usr/bin/env bash
# Check that mpv was built with the VapourSynth filter.
set -euo pipefail

MPV="${MPV:-mpv}"

if ! command -v "$MPV" >/dev/null; then
    echo "SKIP: $MPV not installed"
    exit 0
fi

echo "==> $MPV --version"
"$MPV" --version | head -3

echo "==> vapoursynth filter options"
if ! "$MPV" --vf=vapoursynth=help >/dev/null 2>&1; then
    echo "FAIL: mpv has no vapoursynth filter"
    exit 1
fi

"$MPV" --vf=vapoursynth=help

echo "PASS: vapoursynth filter available"
