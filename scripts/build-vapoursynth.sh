#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$BUILD_ROOT/vapoursynth"

# R79 is the last release before vapoursynth.pyx used the Python 3.15
# sentinel() builtin, which the distro Cython (3.1.6) cannot compile.
VS_TAG="${VS_TAG:-R79}"

clone_repo https://github.com/vapoursynth/vapoursynth.git "$SRC" --branch "$VS_TAG"

PY_PURELIB="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"

meson setup "$SRC/build" "$SRC" \
    --prefix="$PREFIX" \
    --buildtype=release \
    -Denable_x86_asm=true \
    -Dpython.purelibdir="$PY_PURELIB" \
    -Dpython.platlibdir="$PY_PURELIB"
ninja -C "$SRC/build" -j "$JOBS"
ninja -C "$SRC/build" install

# VapourSynth installs into the Python purelib; expose the pieces mpv needs:
#   - pkg-config module (mpv probes `vapoursynth-script` then `vapoursynth`)
#   - libvsscript/libvapoursynth on the loader path (mpv dlopens them by name)
#   - vspipe on PATH
#   - a plugins directory for the RIFE filter
VS_PKG="$PY_PURELIB/vapoursynth"
if [[ ! -d "$VS_PKG" ]]; then
    echo "could not locate installed VapourSynth package at $VS_PKG" >&2
    exit 1
fi

install_tree "VapourSynth directories created under $PREFIX" \
    mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/bin" "$VS_PKG/plugins"

# RIFE derives its install dir as <pkgconfig libdir>/vapoursynth. Point libdir
# at PREFIX/lib and link PREFIX/lib/vapoursynth to VapourSynth's autoloaded
# plugin directory so `librife.so` and its models land where they are found.
install_tree "VapourSynth plugin directory linked" \
    ln -sfn "$VS_PKG/plugins" "$PREFIX/lib/vapoursynth"

# The stock .pc omits libdir/vapoursynth-script, so write one that supplies them.
PC_TMP="$(mktemp)"
cat > "$PC_TMP" <<EOF
prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$VS_PKG/include

Name: vapoursynth
Description: A frameserver for the 21st century
Version: 80
Cflags: -I\${includedir}
EOF
install_tree "VapourSynth pkg-config installed" \
    cp "$PC_TMP" "$PREFIX/lib/pkgconfig/vapoursynth.pc"
rm -f "$PC_TMP"
install_tree "vspipe installed" \
    ln -sf "$VS_PKG/vspipe" "$PREFIX/bin/vspipe"
install_tree "VapourSynth libraries linked" \
    ln -sf "$VS_PKG/libvsscript.so" "$PREFIX/lib/libvsscript.so"
install_tree "VapourSynth library linked" \
    ln -sf "$VS_PKG/libvapoursynth.so" "$PREFIX/lib/libvapoursynth.so"
sudo ldconfig

# VSScript needs the Python executable/library paths pinned per interpreter
# before vspipe or mpv can initialise it. VSScript keys the lookup on the path
# dladdr reports for the loaded library, which is the PREFIX symlink when mpv
# dlopens it by name, so record the entry under both paths.
VSS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/vapoursynth/vapoursynth.toml"
mkdir -p "$(dirname "$VSS_CONFIG")"
python3 -m vapoursynth config
python3 - "$VSS_CONFIG" "$VS_PKG/libvsscript.so" "$PREFIX/lib/libvsscript.so" <<'PY'
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
package_key, prefix_key = sys.argv[2], sys.argv[3]

lines = config_path.read_text().splitlines()
entry = next((l for l in lines if l.startswith(f'"{package_key}"')), None)
if entry and not any(l.startswith(f'"{prefix_key}"') for l in lines):
    lines.append(entry.replace(package_key, prefix_key, 1))
    config_path.write_text("\n".join(lines) + "\n")
PY

echo "VapourSynth installed: $VS_PKG"
pkg-config --modversion vapoursynth
python3 -c 'import vapoursynth; print("VapourSynth", vapoursynth.__version__)'
