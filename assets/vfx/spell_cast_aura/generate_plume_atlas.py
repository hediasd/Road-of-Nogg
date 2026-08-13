"""Generate the original eleven-state angular-U/height-V plume atlas.

The output is project-authored procedural artwork, not pixels extracted from
the supplied game screenshots. Run from any directory with Python + Pillow.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image


FRAME_COUNT = 11
CELL_SIZE = 64
GROUP_COUNT = 4
OUTPUT_PATH = Path(__file__).with_name("plume_flow_atlas.png")

BASE_CENTERS = (0.04, 0.30, 0.57, 0.82)
BASE_WIDTHS = (0.078, 0.060, 0.086, 0.070)
BASE_HEIGHTS = (0.84, 0.68, 0.94, 0.78)
BASE_LEANS = (0.050, -0.038, 0.072, -0.052)


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def lerp(start: float, end: float, weight: float) -> float:
    return start + (end - start) * weight


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return float(value >= edge1)
    t = clamp((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def wrapped_distance(a: float, b: float) -> float:
    return (a - b + 0.5) % 1.0 - 0.5


def plume_field(angular_u: float, height_v: float, state: float, frame: int) -> float:
    field = 0.0
    secondary = 0.0
    for group in range(GROUP_COUNT):
        group_phase = group * 1.731 + frame * 0.683
        center_shift = (
            math.sin(group_phase) * 0.026
            + math.sin(state * math.tau + group * 0.91) * 0.018
        )
        center = BASE_CENTERS[group] + center_shift
        lean = BASE_LEANS[group] + math.cos(group_phase * 0.77) * 0.018
        bent_center = center + lean * height_v**1.28
        width_change = 0.82 + 0.22 * math.sin(group_phase * 1.13 + 0.4)
        width = BASE_WIDTHS[group] * width_change * lerp(0.92, 1.20, height_v)
        distance_u = abs(wrapped_distance(angular_u, bent_center))
        lateral = math.exp(-0.5 * (distance_u / max(width, 0.001)) ** 2.0)

        height_change = 0.90 + 0.10 * math.sin(group_phase * 0.89 - 0.5)
        plume_height = clamp(BASE_HEIGHTS[group] * height_change, 0.48, 0.98)
        root = smoothstep(0.0, 0.075 + (group % 2) * 0.025, height_v)
        tip = 1.0 - smoothstep(plume_height - 0.21, plume_height, height_v)
        body = clamp(root * tip) ** 1.15
        lobe = lateral * body
        field = max(field, lobe * (0.72 + 0.16 * math.sin(group_phase + 1.2)))

        # A weaker offset shoulder breaks the printed-sunburst rhythm while
        # remaining part of the same continuous alpha field.
        shoulder_center = bent_center - lean * 0.55 + 0.035 * math.sin(group_phase * 1.4)
        shoulder_distance = abs(wrapped_distance(angular_u, shoulder_center))
        shoulder_width = width * (1.28 + 0.12 * math.cos(group_phase))
        shoulder = math.exp(-0.5 * (shoulder_distance / shoulder_width) ** 2.0)
        shoulder_tip = 1.0 - smoothstep(
            plume_height * 0.50, plume_height * 0.82, height_v
        )
        secondary += shoulder * root * shoulder_tip * 0.032

    # A continuous low root haze binds the groups into one curtain. Periodic
    # harmonics preserve the exact U seam without creating thin rays.
    root_haze = (
        0.16
        + 0.035 * math.sin(angular_u * math.tau * 2.0 + state * 1.7)
        + 0.025 * math.sin(angular_u * math.tau * 5.0 - state * 2.1)
    ) * smoothstep(0.0, 0.045, height_v) * (
        1.0 - smoothstep(0.10, 0.34, height_v)
    )
    upper_feather = 1.0 - smoothstep(0.82, 1.0, height_v)
    return clamp((field + secondary + root_haze) * upper_feather)


def generate() -> Image.Image:
    atlas = Image.new("RGBA", (CELL_SIZE * FRAME_COUNT, CELL_SIZE))
    pixels: list[tuple[int, int, int, int]] = []
    for y in range(CELL_SIZE):
        height_v = y / (CELL_SIZE - 1)
        for frame in range(FRAME_COUNT):
            state = frame / (FRAME_COUNT - 1)
            for x in range(CELL_SIZE):
                # Both angular endpoints are included and therefore identical.
                angular_u = x / (CELL_SIZE - 1)
                alpha = round(plume_field(angular_u, height_v, state, frame) * 255)
                pixels.append((255, 255, 255, alpha))
    atlas.putdata(pixels)
    return atlas


def validate_seams(atlas: Image.Image) -> None:
    for frame in range(FRAME_COUNT):
        left = frame * CELL_SIZE
        right = left + CELL_SIZE - 1
        for y in range(CELL_SIZE):
            if atlas.getpixel((left, y)) != atlas.getpixel((right, y)):
                raise ValueError(f"Non-periodic U seam in frame {frame + 1}, row {y}")


if __name__ == "__main__":
    image = generate()
    validate_seams(image)
    image.save(OUTPUT_PATH, optimize=True)
    print(f"Generated {OUTPUT_PATH} ({image.width}x{image.height})")
