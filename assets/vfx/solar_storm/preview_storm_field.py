"""Offline preview renderer for the Solar Storm coronagraph field.

This is the authoring loop for `solar_storm_field.gdshader`. Every function is
written so it ports to GLSL line for line -- no numpy, no vectorized tricks --
and the constants below mirror `SolarStormProfile`. Iterating here and porting
the result is far cheaper than an engine launch per attempt.

Stdlib only, deliberately: this host has neither numpy nor Pillow, so the PNG
writer is hand-rolled over `zlib`. No source image pixels are read; the field is
project-authored from measurements taken by eye.

    python assets/vfx/solar_storm/preview_storm_field.py out.png

**The engine remains the acceptance surface.** A match here says the field maths
is right, not that the effect is -- only `VFXDebugScene` renders it on the real
panel, at the real resolution, through the real retro pipeline. Two framing
faults in this effect were invisible here and obvious there: the occulter anchor
and the panel proportions.
"""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

TAU = 6.28318530718

ANCHOR = (0.435, 0.118)          # occulter centre in panel UV, off-centre
ASPECT = 1.207

OCCULTER_RADIUS = 0.115
OCCULTER_EDGE = 0.010
LIMB_RADIUS = 0.072             # thin bright circle drawn inside the disk
LIMB_WIDTH = 0.005
LIMB_GAIN = 0.85

CORONA_INNER = 0.115
CORONA_FALLOFF = 0.78
CORONA_GAIN = 0.66

STREAMER_COUNT = 15.0
STREAMER_SHARPNESS = 1.5
STREAMER_GAIN = 1.1
STREAMER_REACH = 0.55
STREAMER_WARP = 0.018
STREAMER_BROAD = 0.62
STREAMER_THRESHOLD = 0.4

ARC_RADIUS = 0.44
ARC_WIDTH = 0.028
ARC_GAIN = 1.05
ARC_WARP = 0.075
ARC_SPAN = 0.62                 # fraction of a turn the front covers

FOV_RADIUS = 0.78
FOV_EDGE = 0.26

GRAIN = 0.055
BLACK_LIFT = 0.012
EXPOSURE = 1.0

# Heat ramp measured by eye from the source: deep red rim, through orange, into
# the near-white cores of the streamers and the front.
RAMP = (
    (0.00, (0.05, 0.004, 0.002)),
    (0.16, (0.34, 0.030, 0.008)),
    (0.34, (0.62, 0.110, 0.020)),
    (0.52, (0.84, 0.260, 0.040)),
    (0.70, (0.96, 0.470, 0.090)),
    (0.85, (1.00, 0.700, 0.280)),
    (1.00, (1.00, 0.960, 0.820)),
)


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def smoothstep(e0, e1, v):
    if e0 == e1:
        return float(v >= e1)
    t = clamp((v - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def ramp_color(t):
    t = clamp(t)
    ps, pc = RAMP[0]
    for s, c in RAMP:
        if t <= s:
            span = s - ps
            k = 0.0 if span <= 0 else (t - ps) / span
            return (mix(pc[0], c[0], k), mix(pc[1], c[1], k), mix(pc[2], c[2], k))
        ps, pc = s, c
    return RAMP[-1][1]


def hash_grain(px, py, frame):
    n = px * 374761393 + py * 668265263 + frame * 1442695040888963407
    n = (n ^ (n >> 13)) * 1274126177
    n &= 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def sample(u, v, px, py, frame, progress=1.0):
    x = (u - ANCHOR[0]) * ASPECT
    y = v - ANCHOR[1]
    r = math.sqrt(x * x + y * y)
    theta = math.atan2(y, x) / TAU          # 0..1 around the disk

    # --- corona: the broad radial glow behind everything -------------------
    corona = math.exp(-max(r - CORONA_INNER, 0.0) / CORONA_FALLOFF)
    corona *= smoothstep(OCCULTER_RADIUS - 0.02, OCCULTER_RADIUS + 0.06, r)
    corona *= CORONA_GAIN

    # --- streamers: angular filaments radiating from behind the disk -------
    # Streams are built from summed octaves at incommensurate frequencies rather
    # than one periodic spoke function. A single sine to a power can only make
    # identical evenly spaced rays; summing octaves and thresholding produces
    # streams of genuinely different widths, brightnesses, and spacings, which is
    # what the source actually shows.
    splay = math.sin((r * 2.1 + 0.4) * TAU) * STREAMER_WARP
    t = theta + splay
    broad = (
        math.sin((t * 3.1 + 0.00) * TAU) * 0.50
        + math.sin((t * 5.7 - 1.30) * TAU) * 0.30
        + math.sin((t * 11.3 + 2.10) * TAU) * 0.20
    )
    fine = (
        math.sin((t * 8.3 + 0.90) * TAU) * 0.55
        + math.sin((t * 17.1 - 0.40) * TAU) * 0.45
    )
    field = 0.5 + 0.5 * (broad * STREAMER_BROAD + fine * (1.0 - STREAMER_BROAD))
    # Thresholding rather than exponentiating: the cut is what separates streams
    # from background, and moving it changes their width without dimming them.
    streamer = pow(smoothstep(STREAMER_THRESHOLD, 1.0, field), STREAMER_SHARPNESS)
    # A second, much slower octave gates whole regions on and off, so the fan
    # clumps into active and quiet sectors instead of covering every angle.
    gate = 0.5 + 0.5 * math.sin((theta * 2.3 - 0.6) * TAU)
    streamer *= 0.18 + 1.25 * gate
    streamer *= math.exp(-max(r - CORONA_INNER, 0.0) / STREAMER_REACH)
    streamer *= smoothstep(OCCULTER_RADIUS, OCCULTER_RADIUS + 0.05, r)
    # The source's activity fans downward; the upper hemisphere is much quieter.
    streamer *= mix(0.12, 1.0, smoothstep(-0.10, 0.22, y))
    streamer *= STREAMER_GAIN

    # --- front: the bright curved CME loop ---------------------------------
    arc_r = ARC_RADIUS * progress
    warped_r = r + math.sin((theta * 5.0 + 0.3) * TAU) * ARC_WARP
    arc = math.exp(-((warped_r - arc_r) / max(ARC_WIDTH, 1e-4)) ** 2)
    # Angular window: the front is a loop over the lower hemisphere, not a ring.
    # The `+ 0.5` before the wrap is what makes this a distance *from* the span's
    # centre; without it the window is inverted and the front vanishes exactly
    # where it should be brightest.
    angular = clamp(
        1.0 - abs(((theta - 0.25 + 0.5) % 1.0) - 0.5) / (ARC_SPAN * 0.5)
    )
    arc *= smoothstep(0.0, 1.0, angular) * ARC_GAIN

    intensity = corona + streamer + arc

    # --- occulter and field of view ----------------------------------------
    disk = smoothstep(OCCULTER_RADIUS - OCCULTER_EDGE, OCCULTER_RADIUS, r)
    limb = math.exp(-((r - LIMB_RADIUS) / max(LIMB_WIDTH, 1e-4)) ** 2) * LIMB_GAIN
    fov = 1.0 - smoothstep(FOV_RADIUS - FOV_EDGE, FOV_RADIUS, r)

    intensity = (intensity * disk + limb) * fov

    red, green, blue = ramp_color(clamp(intensity * EXPOSURE))
    grain = (hash_grain(px, py, frame) - 0.5) * GRAIN * fov
    lift = BLACK_LIFT * fov
    return (clamp(red + grain + lift), clamp(green + grain + lift),
            clamp(blue + grain + lift))


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def render(path, w, h, frame=0, progress=1.0):
    rows = []
    for py in range(h):
        row = bytearray()
        v = (py + 0.5) / h
        for px in range(w):
            u = (px + 0.5) / w
            r, g, b = sample(u, v, px, py, frame, progress)
            row += bytes((int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5)))
        rows.append(row)
    write_png(path, w, h, rows)


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "solar_preview.png")
    render(out, 350, 290)
    print(f"wrote {out}")
