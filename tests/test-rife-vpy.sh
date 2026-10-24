#!/usr/bin/env bash
# Run a synthetic YUV clip through rife.vpy with vspipe and check that RIFE
# raises the frame count and frame rate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VPY="$REPO_ROOT/vapoursynth/rife.vpy"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v vspipe >/dev/null; then
    echo "SKIP: vspipe not installed"
    exit 0
fi

echo "==> syntax check"
python3 -c "import ast,sys; ast.parse(open('$VPY').read())"

# The script's default model may not be installed on this host; point it at
# whichever model is present so the test exercises the pipeline without network.
MODELS_DIR="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')/vapoursynth/plugins/models"
MAP="$(sed -n 's/^[[:space:]]*\[\([0-9]\+\)\]="\?\([^")]*\)"\?$/\1 \2/p' "$REPO_ROOT/scripts/fetch-models.sh")"
VPY_UNDER_TEST="$VPY"
if [[ -d "$MODELS_DIR" ]]; then
    want_dir="$(awk -v v="$(sed -n 's/^MODEL = //p' "$VPY")" '$1==v{print $2; exit}' <<<"$MAP")"
    if [[ -n "$want_dir" && ! -f "$MODELS_DIR/$want_dir/flownet.param" ]]; then
        installed_id=""
        for dir in "$MODELS_DIR"/*/; do
            [[ -f "$dir/flownet.param" ]] || continue
            name="$(basename "$dir")"
            id="$(awk -v d="$name" '$2==d{print $1; exit}' <<<"$MAP")"
            [[ -n "$id" ]] && { installed_id="$id"; break; }
        done
        if [[ -n "$installed_id" ]]; then
            echo "==> model $want_dir not installed, using model $installed_id for the test"
            VPY_UNDER_TEST="$WORK/rife.vpy"
            sed "s/^MODEL = .*/MODEL = $installed_id/" "$VPY" > "$VPY_UNDER_TEST"
        fi
    fi
fi

# mpv provides video_in and container_fps; emulate both for vspipe.
cat > "$WORK/harness.vpy" <<EOF
import vapoursynth as vs
core = vs.core
video_in = core.std.BlankClip(width=64, height=64, length=4, fpsnum=24,
                              fpsden=1, format=vs.YUV420P8)
video_in = core.std.Expr(video_in, expr=["x 4 +", "x 4 +", "x 4 +"])
video_in = core.std.SetFrameProps(video_in, _Matrix=6, _ColorRange=1)
container_fps = 24.0
exec(compile(open("$VPY_UNDER_TEST").read(), "$VPY_UNDER_TEST", "exec"))
EOF

echo "==> running RIFE via vspipe"
vspipe --info "$WORK/harness.vpy" > "$WORK/info.txt" 2> "$WORK/err.txt" || {
    echo "FAIL: vspipe failed"
    cat "$WORK/err.txt"
    exit 1
}

cat "$WORK/info.txt"

frames="$(sed -n 's/^Frames: //p' "$WORK/info.txt")"
fps="$(sed -n 's/^FPS: //p' "$WORK/info.txt")"

if [[ "$frames" != "8" ]]; then
    echo "FAIL: expected 8 frames, got '$frames'"
    exit 1
fi

if [[ "$fps" != 48/1* ]]; then
    echo "FAIL: expected 48/1 fps, got '$fps'"
    exit 1
fi

echo "PASS: 4 frames @24fps -> $frames frames @$fps"
