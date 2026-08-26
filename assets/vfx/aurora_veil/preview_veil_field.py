"""Offline preview renderer for the Aurora Veil screen-space field.

This is the authoring loop for `aurora_veil_field.gdshader`. Every function is
written so it ports to GLSL line for line -- no numpy, no vectorized tricks,
only scalar math that exists in the shading language -- and the constants below
are the same values `AuroraVeilProfile` holds. Changing the look here and
porting the result is far cheaper than an engine launch per iteration, which is
the whole reason this file exists.

Stdlib only, deliberately: this host has neither numpy nor Pillow, so the PNG
writer is hand-rolled over `zlib`. No source screenshot pixels are read; the
field is project-authored from measurements taken by eye.

    python assets/vfx/aurora_veil/preview_veil_field.py out.png

**The engine remains the acceptance surface.** A match here is evidence the
math is right, not that the effect is right -- only `VFXDebugScene` renders it
through the real retro pipeline at the real resolution.
"""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

TAU = 6.28318530718

# --- Authored field parameters ---------------------------------------------
# ESTIMATED from the source frame by eye; the numbers that survive iteration
# become the profile constants.
MIRROR_AXIS = 0.5
CORE_X = 0.02
CORE_M = 0.22
# The colour sweep and the brightness envelope are separate ellipses. One
# ellipse cannot be both a fast left-to-right hue run and a tall soft silhouette,
# and collapsing them is what makes the field read as a glowing ball.
BAND_RADIUS_X = 0.34
BAND_RADIUS_M = 0.48
ENV_RADIUS_X = 0.44
ENV_RADIUS_M = 0.45
SEAM_WIDTH = 0.055
SEAM_FLOOR = 0.78
LOWER_BLEND = 0.060
LOWER_COMPRESS = 1.12
LOWER_DIM = 0.96
LOWER_SMEAR = 0.010
RIPPLE_FREQUENCY = 7.5
RIPPLE_DEPTH = 0.075
BAND_SCALE = 0.86
BAND_OFFSET = 0.0
WARP_AMPLITUDE = 0.030
BAND_WARP_AMPLITUDE = 0.085
FALLOFF_KNEE = 0.55
FALLOFF_SOFT = 1.4
INTENSITY = 1.12
GRAIN_STRENGTH = 0.05
BLACK_LIFT = 0.022

# MEASURED-by-eye ramp from the source: pale core through the warm midrange
# into magenta, violet, and the deep blue outer field.
RAMP = (
    (0.00, (0.87, 0.89, 0.69)),
    (0.13, (0.93, 0.84, 0.47)),
    (0.29, (0.91, 0.66, 0.38)),
    (0.42, (0.88, 0.54, 0.46)),
    (0.55, (0.83, 0.45, 0.56)),
    (0.67, (0.72, 0.40, 0.63)),
    (0.74, (0.59, 0.36, 0.62)),
    (0.87, (0.36, 0.28, 0.55)),
    (1.00, (0.14, 0.15, 0.31)),
)


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return float(value >= edge1)
    t = clamp((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def mix(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def ramp_color(t: float) -> tuple[float, float, float]:
    t = clamp(t)
    previous_stop, previous_color = RAMP[0]
    for stop, color in RAMP:
        if t <= stop:
            span = stop - previous_stop
            local = 0.0 if span <= 0.0 else (t - previous_stop) / span
            return (
                mix(previous_color[0], color[0], local),
                mix(previous_color[1], color[1], local),
                mix(previous_color[2], color[2], local),
            )
        previous_stop, previous_color = stop, color
    return RAMP[-1][1]


def warp(x: float, m: float) -> tuple[float, float]:
    """Low-frequency domain warp. Keeps the bands from reading as clean rings."""
    wx = (
        math.sin((m * 2.3 + 0.31) * TAU) * 0.55
        + math.sin((m * 4.7 - x * 1.9 + 0.13) * TAU) * 0.28
    )
    wm = (
        math.sin((x * 2.9 - 0.21) * TAU) * 0.48
        + math.sin((x * 5.3 + m * 2.1 + 0.57) * TAU) * 0.24
    )
    return x + wx * WARP_AMPLITUDE, m + wm * WARP_AMPLITUDE


def hash_grain(px: int, py: int, frame: int) -> float:
    n = px * 374761393 + py * 668265263 + frame * 1442695040888963407
    n = (n ^ (n >> 13)) * 1274126177
    n &= 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def veil_sample(u: float, v: float, px: int, py: int, frame: int):
    # The reflected half is blended in over a band rather than switched on at
    # the axis. A hard switch makes every lower-half modifier land as a
    # one-pixel discontinuity, which reads as a drawn line across the seam.
    below = smoothstep(0.0, LOWER_BLEND, v - MIRROR_AXIS)
    m = abs(v - MIRROR_AXIS) * mix(1.0, LOWER_COMPRESS, below)

    wx, wm = warp(u, m)
    wx += math.sin((m * 6.1 + 0.4) * TAU) * LOWER_SMEAR * below

    # Envelope: the silhouette. Warped only slightly, so the outline stays soft.
    ex = (wx - CORE_X) / ENV_RADIUS_X
    em = (wm - CORE_M) / ENV_RADIUS_M
    env_r = math.sqrt(ex * ex + em * em)

    # Bands: the colour sweep. Warped hard, so the interference contours flow
    # instead of ringing, without disturbing the silhouette above.
    band_warp = (
        math.sin((m * 1.7 + u * 0.9 + 0.22) * TAU) * 0.62
        + math.sin((m * 3.1 - u * 2.4 + 0.71) * TAU) * 0.27
    ) * BAND_WARP_AMPLITUDE
    bx = (wx - CORE_X) / BAND_RADIUS_X
    bm = (wm - CORE_M) / BAND_RADIUS_M
    band_r = math.sqrt(bx * bx + bm * bm) + band_warp

    band = clamp(band_r * BAND_SCALE + BAND_OFFSET)
    red, green, blue = ramp_color(band)

    falloff = 1.0 - smoothstep(FALLOFF_KNEE, FALLOFF_SOFT, env_r)
    seam_distance = abs(v - MIRROR_AXIS) / SEAM_WIDTH
    seam = mix(SEAM_FLOOR, 1.0, clamp(1.0 - math.exp(-seam_distance * seam_distance)))

    # Horizontal ripple striations, reflected half only. This is the cue that
    # reads the lower lobe as a reflection rather than a duplicated blob.
    ripple = 1.0 + math.sin((m * RIPPLE_FREQUENCY + 0.17) * TAU) * RIPPLE_DEPTH * below

    energy = falloff * seam * INTENSITY * ripple * mix(1.0, LOWER_DIM, below)

    grain = (hash_grain(px, py, frame) - 0.5) * GRAIN_STRENGTH
    return (
        clamp(red * energy + grain + BLACK_LIFT),
        clamp(green * energy + grain + BLACK_LIFT),
        clamp(blue * energy + grain + BLACK_LIFT),
    )


def write_png(path: Path, width: int, height: int, rows: list[bytearray]) -> None:
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def render(path: Path, width: int, height: int, frame: int = 0) -> None:
    rows = []
    for py in range(height):
        row = bytearray()
        v = (py + 0.5) / height
        for px in range(width):
            u = (px + 0.5) / width
            red, green, blue = veil_sample(u, v, px, py, frame)
            row += bytes(
                (int(red * 255 + 0.5), int(green * 255 + 0.5), int(blue * 255 + 0.5))
            )
        rows.append(row)
    write_png(path, width, height, rows)


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "veil_preview.png")
    render(out, 306, 243)
    print(f"wrote {out}")
