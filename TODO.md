- [x] add RIFE (Real-Time Intermediate Flow Estimation for Video Frame
      Interpolation) support to MPV (https://mpv.io/)
- [x] build a snap
- [x] fix snap audio: `--ao=pipewire` fails with "can't make support.system
      handle" because the pipewire modules/config are not bundled and the
      pipewire socket is not allowed by AppArmor
- [x] fix video output: X11 (`x11`/`xv`/`x11egl`) was silently compiled out
      because `libxss-dev` was missing, and Wayland failed under confinement
      because `XDG_RUNTIME_DIR` is remapped so a relative `WAYLAND_DISPLAY` no
      longer resolves
- [x] fix snap RIFE: VSScript could not resolve Python after a refresh (config
      keyed to the revision path) and no Vulkan ICD was bundled, so RIFE failed
      with "failed to create GPU instance"
- [x] fix snap vpy path: the documented `--vf=vapoursynth=vapoursynth/rife.vpy`
      is checkout-relative and failed from other directories; the launcher now
      resolves it to the bundled script
- [x] improve real-time throughput: auto-enable UHD flow downscaling for 1080p+
      clips; `GPU_THREAD` measured faster at the plugin default (2) than at the
      compute-queue count (1), so it is left at 2
- [x] fix `--hwdec=auto`: the snap staged `libva2` but no VA-API driver, so
      hardware decode silently fell back to software; bundle
      `intel-media-va-driver`/`i965-va-driver`
- [x] speed up interpolation: default to the single-network rife-v4.17-lite
      model (id 55) and bundle it, rather than the three-network rife-v2.3
      (id 5)
- [x] add `SCALE` option: interpolating at a fraction of the source resolution
      measured ~4x faster on the real 4K clip (12 output frames: 379 s at 1.0 vs
      94 s at 0.5); default 0.5
