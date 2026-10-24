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
- Audio: the bundled mpv has both `pipewire` and `pulse` outputs. `--ao=pipewire`
  needs `libpipewire-0.3-modules` (the client-side modules) and
  `pipewire-bin`'s `client.conf`, which the compiled-in `/usr` paths cannot find
  inside the base snap, so the launcher sets `PIPEWIRE_MODULE_DIR`,
  `SPA_PLUGIN_DIR` and `PIPEWIRE_CONFIG_DIR`. The socket itself requires the
  `pipewire` interface, which is `deny-auto-connection`, so the launcher also
  points `PIPEWIRE_RUNTIME_DIR`/`PULSE_SERVER` at the host user runtime dir
  (`${XDG_RUNTIME_DIR%/*}`); AppArmor only allows the host socket once the plug
  is connected. Without the pipewire plug, `pulse` against the host
  pipewire-pulse socket is the fallback.
- Video: mpv's meson only enables X11 when `x11`, `xscrnsaver`, `xext`,
  `xpresent` and `xrandr` are all found. `libxss-dev` was absent, so `x11`,
  `xv`, `x11egl` and `x11vk` were silently compiled out and every GPU vo failed
  with `Error opening/initializing the selected video_out`. Adding `libxss-dev`
  and `libxv-dev` to the build deps restores them; the matching runtime
  (`libxss1`, `libxv1`, `libxpresent1`, `libxrandr2`, `libgl1`, `libglx0`,
  `libopengl0`, `libegl-mesa0`, `libglx-mesa0`, `libxcb-glx0`, `libxxf86vm1`)
  is staged because the base has none of it.
- Wayland outputs (`wlshm`, `dmabuf-wayland`) were already compiled in. Snapd
  remaps `XDG_RUNTIME_DIR` to `/run/user/<uid>/snap.<name>`, which still only
  contains the snap's own sockets, so a relative `WAYLAND_DISPLAY` such as
  `wayland-0` no longer resolves to the compositor socket in the host runtime
  dir. The launcher rewrites a relative `WAYLAND_DISPLAY` to an absolute path
  under `${XDG_RUNTIME_DIR%/*}`; the `wayland` interface allows the socket.
- Vulkan: the snap carries `libvulkan1` but no ICD, and the loader's default
  `/usr/share/vulkan/icd.d` resolves to the base snap, which has none, so every
  Vulkan context and RIFE itself fail with `VK_ERROR_INCOMPATIBLE_DRIVER` /
  `failed to create GPU instance`. `mesa-vulkan-drivers` (plus its deps
  `libdisplay-info3`, `libllvm21`, `libelf1t64`, `libxshmfence1`, `libzstd1`,
  `zlib1g`) is staged and the launcher sets `VK_ADD_DRIVER_FILES`. That variable
  appends to the loader defaults, so snapd's host-provided NVIDIA ICDs still
  work. `LIBGL_DRIVERS_PATH`/`LIBVA_DRIVERS_PATH` and
  `__EGL_VENDOR_LIBRARY_FILENAMES` point at the bundled Mesa DRI drivers and EGL
  vendor file, and `libgl1-mesa-dri` is staged for the GL/VA-API DRI drivers.
- VSScript: the interpreter lookup is keyed by the path `libvsscript.so` was
  loaded from. That path contains the snap revision, so a `vapoursynth.toml`
  written before a refresh no longer matches and mpv reports "Python executable
  and library path couldn't be determined". The launcher regenerates the config
  whenever the current key is absent (`vapoursynth config` merges, leaving stale
  keys behind).
- The README's `--vf=vapoursynth=vapoursynth/rife.vpy` is relative to a source
  checkout. mpv passes the string straight to VSScript, which resolves it
  against the current directory, so from an arbitrary media folder it fails with
  `[Errno 2] No such file or directory: 'vapoursynth/rife.vpy'`. The launcher
  rewrites any relative `vapoursynth=` argument that is absent from the current
  directory but exists under `$SNAP` to its absolute bundled path.
- VA-API: `libva2` alone is not enough for `--hwdec=auto`. Without a driver
  library in `LIBVA_DRIVERS_PATH` libva logs `va_openDriver() returns -1` and
  silently falls back to software decoding, which then competes with RIFE for
  CPU. `intel-media-va-driver` (GEN8+, iHD) and `i965-va-driver` (older Intel)
  are staged; Mesa's own VA drivers for AMD/others come with `libgl1-mesa-dri`.
- Model cost: the original default, model 5 (rife-v2.3), runs three networks
  (flownet + contextnet + fusionnet); the v4 family runs only flownet. On the
  same 640x360 llvmpipe benchmark rife-v4.17-lite was ~5.6x faster (0.89 vs
  0.16 fps), so it is the bundled default (id 55). rife-v2.3 stays bundled for
  users who want the higher quality and can afford the cost.
- Throughput knobs, measured on the real 2160x1080 10-bit clip: RIFE's cost
  scales with pixel count and optical flow dominates, so `SCALE` (interpolate at
  a fraction of the source size, then upscale) is the strongest lever: 12 output
  frames took 379 s at `SCALE=1.0` versus 94 s at `SCALE=0.5`. `GPU_THREAD=2`
  beat `GPU_THREAD=1` (33 s vs 47 s for the same 8 frames), so it is left at 2.
  `UHD` on its own barely changed the time (80 s vs 87 s). Even at `SCALE=0.5`
  this iGPU produces roughly one output frame every 7 s versus the 48 fps a 2x
  target needs, so real-time 4K interpolation is out of reach regardless; the
  levers buy a few times, not the ~50x required.

## Disk pressure

Building VapourSynth, ncnn/RIFE and mpv from source is disk heavy. Build trees
live under `/var/tmp` and are gitignored; prune them after installing.
