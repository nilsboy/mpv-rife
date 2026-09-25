# mpv-rife

RIFE (Real-Time Intermediate Flow Estimation) frame interpolation for
[mpv](https://mpv.io/), exposed through VapourSynth, plus an all-in-one snap.

RIFE synthesises intermediate frames with a neural network running on Vulkan,
raising the effective frame rate of a video for smoother motion.

## How it works

```
mpv --vf=vapoursynth=vapoursynth/rife.vpy  video.mkv
```

mpv's `vapoursynth` filter runs `vapoursynth/rife.vpy`. That script takes the
decoded frames via `video_in`, optionally detects scene changes, runs the RIFE
filter, and returns the interpolated clip as `video_out`.

The RIFE plugin is `styler00dollar/VapourSynth-RIFE-ncnn-Vulkan`, a VapourSynth
wrapper around `nihui/rife-ncnn-vulkan`.

## Requirements

- A Vulkan-capable GPU (RIFE runs on Vulkan). Intel/AMD via Mesa or NVIDIA
  proprietary drivers both work.
- Linux x86_64. The scripts target Ubuntu but should work on any distro with
  meson/ninja and the listed dev packages.

## Build

Everything is built from source because Ubuntu does not package VapourSynth and
its mpv is not built with VapourSynth support.

```sh
sudo scripts/install-deps.sh          # distro build dependencies
scripts/build-vapoursynth.sh          # VapourSynth runtime + headers
scripts/build-rife.sh                 # RIFE plugin + models
scripts/build-libplacebo.sh           # libplacebo (only if your distro lacks it)
scripts/build-mpv.sh                  # mpv with -Dvapoursynth=enabled
```

Install to `/usr/local` by default; override with `PREFIX=/your/prefix`.

VapourSynth is pinned to R79: newer releases use the Python 3.15 `sentinel()`
builtin, which the distro Cython (3.1.6) cannot compile.

## Usage

Play a file with interpolation:

```sh
mpv --vf=vapoursynth=vapoursynth/rife.vpy video.mkv
```

Or use the bundled config, which adds a `[rife]` profile and a runtime toggle
bound to `Ctrl+r`:

```sh
mpv --config-dir=mpv --profile=rife video.mkv
```

The toggle script reads the vpy path from `script-opts/rife-toggle.conf`.

### rife.vpy options

Configuration lives at the top of `vapoursynth/rife.vpy`:

| Option | Meaning |
| --- | --- |
| `MODEL` | RIFE model id (see RIFE plugin README); `None` uses the plugin default |
| `FACTOR_NUM`, `FACTOR_DEN` | Frame-rate multiplier, e.g. `2`/`1` doubles the rate |
| `FPS_NUM`, `FPS_DEN` | Explicit target frame rate (overrides the factor) |
| `GPU_ID` | Vulkan device index |
| `SCENE_CHANGE` | Skip interpolation across scene changes |

## Snap

An all-in-one snap bundles mpv, VapourSynth, the RIFE plugin and models. The
snap is built against `core26`, matching this project's Ubuntu 26.04 host:

```sh
cd snap && snapcraft pack
sudo snap install --dangerous ./mpv-rife_*.snap
```

The default managed build uses LXD; `snapcraft pack --destructive-mode` builds
directly on the host (no LXD required) and is what the project targets.

## Tests

```sh
tests/run-tests.sh
```

Covers the vpy script syntax/load and the mpv `vapoursynth` filter availability.
Actual interpolation needs a GPU and is verified manually.

## Notes

See [NOTES.md](NOTES.md) for design and environment details.
