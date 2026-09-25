"""Generate the measured eleven-state haze/ray/root mask atlas.

The artwork is project-authored from normalized measurements in
``source_measurements.json``. No source screenshot pixels are read or copied.
RGB stores continuous haze, sparse ghost rays, and low root striations;
alpha stores their union for inspection. Run with Python + Pillow.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image


FRAME_COUNT = 11
CELL_SIZE = 256
OUTPUT_PATH = Path(__file__).with_name("plume_flow_atlas.png")
MEASUREMENTS_PATH = Path(__file__).with_name("source_measurements.json")

BASE_RAY_CENTERS = tuple(index / 20.0 for index in range(20))
BASE_RAY_WIDTHS = tuple(0.007 + (index % 4) * 0.0014 for index in range(20))


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return float(value >= edge1)
    t = clamp((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def wrapped_distance(a: float, b: float) -> float:
    return (a - b + 0.5) % 1.0 - 0.5


def gaussian(distance: float, width: float) -> float:
    return math.exp(-0.5 * (distance / max(width, 0.0001)) ** 2.0)


def load_measurements() -> list[dict[str, float]]:
    data = json.loads(MEASUREMENTS_PATH.read_text(encoding="utf-8"))
    frames = data["frames"]
    if len(frames) != FRAME_COUNT:
        raise ValueError(f"Expected {FRAME_COUNT} measured frames, got {len(frames)}")
    return frames


def haze_field(u: float, v: float, frame: int, measured: dict[str, float]) -> float:
    state = frame / (FRAME_COUNT - 1)
    # Dense source height is expressed in character heights. The haze carrier
    # is slightly shorter than the character, so this maps the measurement into
    # an intentionally low field while retaining faint shoulder wisps.
    measured_height = clamp(measured["dense_height"] * 0.78, 0.48, 0.76)
    angular_height = measured_height * (
        0.82
        + 0.16 * math.sin(u * math.tau * 2.0 + state * 2.4 + 0.3)
        + 0.085 * math.sin(u * math.tau * 5.0 - state * 1.7 + 1.1)
    )
    upper = 1.0 - smoothstep(angular_height - 0.20, angular_height, v)
    root = smoothstep(0.015, 0.14, v)
    lower_mass = 1.0 - smoothstep(0.16, 0.78, v)
    # The source has no continuous filled bowl. Its apparently broad curtain
    # is overlapping soft angular columns, with only a low root fog joining
    # them. Keep the baseline weak so the projected carrier never reads as a
    # geometric dome.
    broad_modulation = (
        0.075
        + 0.08 * (0.5 + 0.5 * math.sin(u * math.tau * 2.0 + state * 1.4)) ** 2.0
        + 0.07 * (0.5 + 0.5 * math.sin(u * math.tau * 5.0 - state * 2.0 + 0.8)) ** 3.0
    )
    shoulder_wisp = 0.0
    for group in range(14):
        center = (0.018 + group / 14.0 + state * 0.020 * (-1 if group % 2 else 1)) % 1.0
        distance = abs(wrapped_distance(u, center + (v**1.3) * (0.025 - group * 0.011)))
        lobe = gaussian(distance, 0.032 + (group % 3) * 0.007)
        lobe_height = angular_height + 0.08 + 0.035 * math.sin(frame * 0.73 + group * 1.4)
        lobe_tip = 1.0 - smoothstep(lobe_height - 0.18, lobe_height, v)
        shoulder_wisp = max(shoulder_wisp, lobe * lobe_tip * (0.46 + (group % 2) * 0.08))
    root_fog = (1.0 - smoothstep(0.08, 0.30, v)) * 0.22
    measured_energy = clamp(measured["dense_width"] / 3.0, 0.76, 1.04)
    return clamp((broad_modulation * lower_mass + shoulder_wisp + root_fog) * root * upper * measured_energy)


def ray_field(u: float, v: float, frame: int, measured: dict[str, float]) -> float:
    state = frame / (FRAME_COUNT - 1)
    count = int(measured["outer_ray_count"])
    field = 0.0
    # A stable population drifts slightly; measured count selects which rays
    # are active in each state. Reorganization lives in the authored masks,
    # while the shader contributes only a small continuous rotational drift.
    ranked = sorted(
        range(len(BASE_RAY_CENTERS)),
        key=lambda group: math.sin(group * 2.173 + frame * 1.119),
        reverse=True,
    )
    # Measurements describe the visible source fan. A world-space shell shows
    # roughly one hemisphere at once, so author twice that population around
    # 360 degrees to retain the measured on-screen group count at every yaw.
    active = set(ranked[:min(count * 2, len(BASE_RAY_CENTERS))])
    for group, base_center in enumerate(BASE_RAY_CENTERS):
        if group not in active:
            continue
        phase = group * 1.731 + frame * 0.617
        center = base_center + state * (0.018 + (group % 3) * 0.004)
        lean = (0.022 + 0.012 * math.sin(phase)) * (-1 if group % 2 else 1)
        bent_center = center + lean * v**1.35
        base_width = BASE_RAY_WIDTHS[group]
        width = base_width * (1.32 - 0.76 * v)
        lateral_distance = abs(wrapped_distance(u, bent_center))
        lateral = gaussian(lateral_distance, width)

        source_height = clamp(measured["faint_height"] * 0.80, 0.66, 0.84)
        height = clamp(source_height + 0.075 * math.sin(phase * 0.83), 0.58, 0.91)
        local_distance = lateral_distance / max(width, 0.001)
        local_height = height - clamp(local_distance, 0.0, 2.0) ** 1.25 * 0.16
        tip = 1.0 - smoothstep(local_height - 0.22, local_height, v)
        root = smoothstep(0.025 + (group % 2) * 0.018, 0.15, v)
        # Elevated rays are intentionally fainter. This inverts the previous
        # flame crown, where the tallest shapes were also the most opaque.
        height_fade = 1.0 - smoothstep(0.54, 0.94, v) * 0.62
        amplitude = 0.86 + 0.10 * math.sin(phase + 0.4)
        field = max(field, lateral * tip * root * height_fade * amplitude)
    return clamp(field)


def root_detail_field(u: float, v: float, frame: int) -> float:
    if v > 0.31:
        return 0.0
    state = frame / (FRAME_COUNT - 1)
    envelope = smoothstep(0.015, 0.08, v) * (1.0 - smoothstep(0.12, 0.31, v))
    hairlines = 0.0
    for frequency, phase, strength in ((11.0, 0.2, 0.24), (17.0, 1.7, 0.16), (23.0, 2.8, 0.10)):
        wave = 0.5 + 0.5 * math.sin(u * math.tau * frequency + phase + state * 1.1)
        hairlines += wave**7.0 * strength
    return clamp(hairlines * envelope)


def generate() -> Image.Image:
    measurements = load_measurements()
    atlas = Image.new("RGBA", (CELL_SIZE * FRAME_COUNT, CELL_SIZE))
    pixels: list[tuple[int, int, int, int]] = []
    for y in range(CELL_SIZE):
        v = y / (CELL_SIZE - 1)
        for frame in range(FRAME_COUNT):
            measured = measurements[frame]
            for x in range(CELL_SIZE):
                u = x / (CELL_SIZE - 1)
                haze = haze_field(u, v, frame, measured)
                rays = ray_field(u, v, frame, measured)
                root = root_detail_field(u, v, frame)
                union = max(haze, rays, root)
                pixels.append(tuple(round(channel * 255) for channel in (haze, rays, root, union)))
    atlas.putdata(pixels)
    return atlas


def validate_seams(atlas: Image.Image) -> None:
    for frame in range(FRAME_COUNT):
        left = frame * CELL_SIZE
        right = left + CELL_SIZE - 1
        for y in range(CELL_SIZE):
            if atlas.getpixel((left, y)) != atlas.getpixel((right, y)):
                raise ValueError(f"Non-periodic RGB seam in frame {frame + 1}, row {y}")


if __name__ == "__main__":
    image = generate()
    validate_seams(image)
    image.save(OUTPUT_PATH, optimize=True)
    print(f"Generated {OUTPUT_PATH} ({image.width}x{image.height}, RGB masks + union alpha)")
