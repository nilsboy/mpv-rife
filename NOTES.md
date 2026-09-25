# Notes

## Integration path

RIFE is exposed to mpv through VapourSynth. mpv must be built with
`-Dvapoursynth=enabled`; the `vapoursynth` video filter then loads a `.vpy`
script that reads `video_in` and writes `video_out`.

The RIFE filter itself is the VapourSynth plugin from
`styler00dollar/VapourSynth-RIFE-ncnn-Vulkan`, which wraps
`nihui/rife-ncnn-vulkan` (ncnn + Vulkan). It requires an RGB float clip.

## Environment observations

- Build host: Ubuntu 26.04, x86_64, 4 cores, ~7.7 GB RAM, ~4 GB free disk.
- No usable GPU: QEMU virtual VGA (`1234:1111`), no Vulkan ICD, no render node.
  Real interpolation cannot be verified on this machine, but the filter does run
  on llvmpipe for tiny synthetic clips.
- Ubuntu 26.04 does not package VapourSynth; mpv 0.41.0 in apt is built
  without VapourSynth. Everything is built from source.
- `snapcraft` 9.1.2 is installed; `lxd` is installed but not initialised.
  `snapcraft pack --destructive-mode` on the core26 base avoids LXD entirely and
  reuses host build packages.

## VapourSynth version pin

VapourSynth master (post-R80) uses the Python 3.15 `sentinel()` builtin in
`src/cython/vapoursynth.pyx`. The distro Cython (3.1.6) has no such builtin and
fails with `undeclared name not builtin: sentinel`, so a newer Cython is not a
workaround. Pin VapourSynth to **R79**, the last release before `sentinel()` was
introduced. This applies to both `scripts/build-vapoursynth.sh` and the snap's
`source-tag`.

R79's `vapoursynth.pc` also omits `libdir`, which RIFE's meson reads via
`dependency('vapoursynth').get_variable(pkgconfig: 'libdir')` to choose its
plugin directory. Both the build script and the snap's `override-build` install
a `.pc` that supplies `libdir`; without it RIFE installs to a leaked absolute
stage path or fails.

## RIFE source size

The RIFE repository carries hundreds of MB of model weights in its history, so a
plain shallow clone is slow and often fails (`early EOF`). Use a blobless,
sparse checkout (`--filter=blob:none --no-checkout` plus sparse-checkout for
`RIFE pkgconfig subprojects`) and fetch weights separately; the snap does this
in `override-pull`.

## Snap packaging

- Base is `core26` to match the Ubuntu 26.04 host.
- mpv links against a long list of system libraries; under strict confinement
  they must be bundled via `stage-packages` on the `mpv` part. The list was
  derived from snapcraft's library linter output.
- VapourSynth's VSScript needs a Python interpreter. `stage-packages` pulls
  `python3.14` and `libpython3.14`; the launcher points `VSSCRIPT_PATH` at the
  bundled `libvsscript.so` and generates the matching `vapoursynth.toml` entry.
- The `runtime` (nil plugin) part installs the launcher, `mpv.conf`, the toggle
  script and `rife.vpy` from the project directory.

## Disk pressure

Building VapourSynth, ncnn/RIFE and mpv from source is disk heavy. Build trees
live under `/var/tmp` and are gitignored; prune them after installing.
