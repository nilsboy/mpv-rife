# RIFE frame interpolation for mpv's vapoursynth filter.
#
# mpv's VapourSynth bridge only exchanges YUV clips, while RIFE requires an RGB
# float clip, so this script converts to RGBS for the interpolation and back to
# the original format for output.
#
# mpv exposes colour metadata under libavcodec names (_ColorSpace, _ColorRange);
# resize takes the matrix/range as integer arguments, not property names.
#
# Run with:
#   mpv --vf=vapoursynth=/path/to/rife.vpy video.mkv

import vapoursynth as vs

from fractions import Fraction

core = vs.core


# --- configuration -----------------------------------------------------------

# RIFE model id; see the RIFE plugin README. 55 = rife-v4.17-lite, whose single
# lightweight network is comfortably faster than the older multi-network models
# (5 = rife-v2.3) and still supports an arbitrary target frame rate.
MODEL = 55

# Frame-rate multiplier. 2/1 doubles the frame rate.
FACTOR_NUM = 2
FACTOR_DEN = 1

# Explicit target frame rate; overrides the factor when both are set.
FPS_NUM = None
FPS_DEN = None

# Vulkan device index.
GPU_ID = 0

# Interpolation threads. More threads overlap ncnn queue submissions, which
# measured faster than matching the GPU's compute-queue count; None keeps the
# plugin default.
GPU_THREAD = 2

# Interpolate at this fraction of the source size, then scale the result back
# up. RIFE's cost scales with pixel count, so this is the main lever when a GPU
# cannot hit the target frame rate at full resolution. 0.5 roughly quadruples
# throughput at some loss of sharpness; raise toward 1.0 as the GPU allows.
SCALE = 0.5

# UHD mode computes the optical flow at reduced resolution and upscales it,
# which is substantially faster for large frames. None enables it automatically
# for clips at least 1080 pixels tall.
UHD = None

# Skip interpolation across scene changes (runs misc.SCDetect first).
SCENE_CHANGE = False

# -----------------------------------------------------------------------------


def _source_fps(clip):
    # mpv's video_in clip reports 0/0 fps; the real rate is in container_fps.
    if clip.fps_num and clip.fps_den:
        return clip.fps_num, clip.fps_den
    if container_fps:
        frac = Fraction(container_fps).limit_denominator(100000)
        return frac.numerator, frac.denominator
    raise RuntimeError("could not determine source frame rate")


def _color_args(clip):
    # read only the first frame, and only here, to avoid a frame request while
    # the script is still being evaluated.
    props = clip.get_frame(0).props
    matrix = props.get("_ColorSpace", props.get("_Matrix", 6))
    range_ = props.get("_ColorRange", props.get("_Range"))
    color_in = {"matrix_in": matrix}
    color_out = {"matrix": matrix}
    if range_ is not None:
        color_in["range_in"] = int(range_)
        color_out["range"] = int(range_)
    return color_in, color_out


def main():
    clip = video_in
    if clip is None:
        return

    source_color, output_color = _color_args(clip)
    source_num, source_den = _source_fps(clip)

    fps_num = FPS_NUM if FPS_NUM is not None else source_num * FACTOR_NUM
    fps_den = FPS_DEN if FPS_DEN is not None else source_den * FACTOR_DEN

    if SCENE_CHANGE:
        clip = core.misc.SCDetect(clip)

    rgb = core.resize.Bicubic(clip, format=vs.RGBS, **source_color)
    rgb = core.std.RemoveFrameProps(
        rgb, "_Matrix, _Transfer, _Primaries, _ColorRange, _Range"
    )
    # mpv's clip has no usable frame rate, so stamp the source rate on it.
    rgb = core.std.AssumeFPS(rgb, fpsnum=source_num, fpsden=source_den)

    scaled = rgb
    if SCALE != 1.0:
        width = max(2, int(rgb.width * SCALE) & ~1)
        height = max(2, int(rgb.height * SCALE) & ~1)
        scaled = core.resize.Bicubic(rgb, width=width, height=height)

    kwargs = {
        "model": MODEL,
        "fps_num": fps_num,
        "fps_den": fps_den,
        "gpu_id": GPU_ID,
    }
    if GPU_THREAD is not None:
        kwargs["gpu_thread"] = GPU_THREAD
    uhd = UHD if UHD is not None else clip.height >= 1080
    if uhd:
        kwargs["uhd"] = True
    if SCENE_CHANGE:
        kwargs["sc"] = True

    interpolated = core.rife.RIFE(scaled, **kwargs)
    if SCALE != 1.0:
        interpolated = core.resize.Bicubic(
            interpolated, width=rgb.width, height=rgb.height
        )

    # RIFE copies the source's frame properties onto its RGB output; drop them
    # so the RGB->YUV conversion below is accepted.
    interpolated = core.std.RemoveFrameProps(
        interpolated, "_Matrix, _Transfer, _Primaries, _ColorRange, _Range"
    )

    out = core.resize.Bicubic(
        interpolated, format=video_in.format, **output_color
    )
    out.set_output()


main()
