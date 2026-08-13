"""Register and compare Road of Nogg spell-aura renders to the source frames.

The script reads source pixels only from caller-provided paths. It writes a
paired inspection sheet and a JSON report containing measurements and hashes;
it never copies source pixels into project assets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw


FRAME_COUNT = 11
ANGULAR_BINS = 16
ANALYSIS_TOP_MARGIN = 4
METRIC_NAMES = (
    "faint_width",
    "dense_width",
    "faint_height",
    "dense_height",
    "energy_centroid_height",
    "aperture_width",
    "horizontal_band_periodicity",
    "horizontal_edge_ratio",
    "silhouette_plateau_ratio",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", nargs=FRAME_COUNT, type=Path, required=True)
    parser.add_argument("--render", nargs=FRAME_COUNT, type=Path, required=True)
    parser.add_argument(
        "--measurements",
        type=Path,
        default=Path(__file__).with_name("source_measurements.json"),
    )
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--sheet", type=Path, required=True)
    parser.add_argument("--command-label", default="unspecified")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_images(paths: Iterable[Path]) -> list[Image.Image]:
    images: list[Image.Image] = []
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(path)
        with Image.open(path) as image:
            images.append(image.convert("RGBA"))
    return images


def detect_render_body(image: Image.Image) -> tuple[int, int, int, int]:
    """Find the red/orange debug proxy without selecting the cyan aura."""
    xs: list[int] = []
    ys: list[int] = []
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = image.getpixel((x, y))
            if (
                alpha > 0
                and red >= 42
                and red > blue * 1.34 + 4
                and red > green * 1.04
            ):
                xs.append(x)
                ys.append(y)
    if not xs:
        raise ValueError("Could not detect the red/orange target-body proxy")
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def register_render(
    image: Image.Image,
    render_body: tuple[int, int, int, int],
    source_size: tuple[int, int],
    source_body: tuple[int, int, int, int],
) -> Image.Image:
    """Map the proxy's center/bottom and dimensions onto the source character."""
    render_left, render_top, render_right, render_bottom = render_body
    source_left, source_top, source_right, source_bottom = source_body
    render_width = max(render_right - render_left, 1)
    render_height = max(render_bottom - render_top, 1)
    source_width = max(source_right - source_left, 1)
    source_height = max(source_bottom - source_top, 1)
    scale_x = source_width / render_width
    scale_y = source_height / render_height
    render_center = (render_left + render_right) * 0.5
    source_center = (source_left + source_right) * 0.5
    inverse = (
        1.0 / scale_x,
        0.0,
        render_center - source_center / scale_x,
        0.0,
        1.0 / scale_y,
        render_bottom - source_bottom / scale_y,
    )
    return image.transform(
        source_size,
        Image.Transform.AFFINE,
        inverse,
        resample=Image.Resampling.BICUBIC,
    )


def blue_strength(pixel: tuple[int, int, int, int], threshold: int) -> float:
    red, green, blue, alpha = pixel
    if alpha == 0 or blue < threshold or blue <= red * 1.28 or blue <= green * 1.05:
        return 0.0
    chroma = blue - max(red * 1.28, green * 1.05)
    return max(chroma, 1.0) * alpha / 255.0


def in_rect(x: int, y: int, rect: tuple[int, int, int, int]) -> bool:
    left, top, right, bottom = rect
    return left <= x < right and top <= y < bottom


def strength_map(
    image: Image.Image,
    threshold: int,
    exclusion: tuple[int, int, int, int],
    analysis_top: int,
) -> list[list[float]]:
    values = [[0.0] * image.width for _ in range(image.height)]
    pixels = image.load()
    for y in range(max(analysis_top, 0), image.height):
        for x in range(image.width):
            if not in_rect(x, y, exclusion):
                values[y][x] = blue_strength(pixels[x, y], threshold)
    return values


def nonzero_points(values: list[list[float]]) -> list[tuple[int, int, float]]:
    return [
        (x, y, value)
        for y, row in enumerate(values)
        for x, value in enumerate(row)
        if value > 0.0
    ]


def percentile(values: list[int], fraction: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = min(round((len(ordered) - 1) * fraction), len(ordered) - 1)
    return ordered[index]


def palette_metrics(
    image: Image.Image,
    values: list[list[float]],
) -> dict[str, list[int]]:
    channels = [[], [], []]
    pixels = image.load()
    for y, row in enumerate(values):
        for x, value in enumerate(row):
            if value <= 0.0:
                continue
            red, green, blue, _alpha = pixels[x, y]
            channels[0].append(red)
            channels[1].append(green)
            channels[2].append(blue)
    return {
        "p50": [percentile(channel, 0.50) for channel in channels],
        "p90": [percentile(channel, 0.90) for channel in channels],
    }


def aperture_width(
    values: list[list[float]],
    center_x: float,
    body_bottom: int,
    body_width: int,
    body_height: int,
) -> float:
    gaps: list[float] = []
    first_y = max(0, round(body_bottom - body_height * 0.68))
    last_y = min(len(values), round(body_bottom + body_height * 0.10))
    center = round(center_x)
    for y in range(first_y, last_y):
        row = values[y]
        left = [x for x in range(0, center) if row[x] > 0.0]
        right = [x for x in range(center, len(row)) if row[x] > 0.0]
        if not left or not right:
            continue
        gap = min(right) - max(left)
        if body_width * 0.45 <= gap <= body_width * 2.8:
            gaps.append(gap / body_width)
    return round(percentile([round(gap * 10000) for gap in gaps], 0.65) / 10000.0, 4)


def angular_profile(
    values: list[list[float]], center_x: float, body_bottom: int
) -> list[float]:
    bins = [0.0] * ANGULAR_BINS
    for y, row in enumerate(values):
        for x, value in enumerate(row):
            if value <= 0.0:
                continue
            angle = math.atan2(body_bottom - y, x - center_x)
            normalized = (angle + math.pi) / (math.tau)
            index = min(int(normalized * ANGULAR_BINS), ANGULAR_BINS - 1)
            bins[index] += value
    total = sum(bins)
    return [round(value / total, 6) if total else 0.0 for value in bins]


def horizontal_band_periodicity(values: list[list[float]]) -> float:
    row_energy = [sum(row) for row in values]
    radius = 5
    residual: list[float] = []
    for index, value in enumerate(row_energy):
        start = max(index - radius, 0)
        finish = min(index + radius + 1, len(row_energy))
        trend = sum(row_energy[start:finish]) / max(finish - start, 1)
        residual.append(value - trend)
    variance = sum(value * value for value in residual)
    if variance <= 1e-9:
        return 0.0
    strongest = 0.0
    for lag in range(2, min(18, len(residual) // 2)):
        numerator = sum(
            residual[index] * residual[index + lag]
            for index in range(len(residual) - lag)
        )
        denominator = math.sqrt(
            sum(value * value for value in residual[:-lag])
            * sum(value * value for value in residual[lag:])
        )
        if denominator > 1e-9:
            strongest = max(strongest, numerator / denominator)
    return round(max(strongest, 0.0), 6)


def horizontal_edge_ratio(values: list[list[float]]) -> float:
    """Share of mask edge energy carried by horizontal rather than vertical edges."""
    horizontal = 0.0
    vertical = 0.0
    for y, row in enumerate(values):
        if y > 0:
            horizontal += sum(
                abs(value - values[y - 1][x]) for x, value in enumerate(row)
            )
        vertical += sum(abs(row[x] - row[x - 1]) for x in range(1, len(row)))
    total = horizontal + vertical
    return round(horizontal / total, 6) if total > 1e-9 else 0.0


def silhouette_plateau_ratio(values: list[list[float]]) -> float:
    """Fraction of adjacent aura columns sharing an exactly horizontal top edge."""
    if not values:
        return 0.0
    tops: list[int | None] = []
    for x in range(len(values[0])):
        top = next((y for y, row in enumerate(values) if row[x] > 0.0), None)
        tops.append(top)
    horizontal = 0
    compared = 0
    for previous, current in zip(tops, tops[1:]):
        if previous is None or current is None:
            continue
        compared += 1
        if previous == current:
            horizontal += 1
    return round(horizontal / compared, 6) if compared else 0.0


def body_overdraw(
    image: Image.Image, body: tuple[int, int, int, int], threshold: int
) -> float:
    left, top, right, bottom = body
    hits = 0
    area = max((right - left) * (bottom - top), 1)
    pixels = image.load()
    for y in range(top, bottom):
        for x in range(left, right):
            if blue_strength(pixels[x, y], threshold) > 0.0:
                hits += 1
    return round(hits / area, 6)


def measure_frame(
    image: Image.Image,
    body: tuple[int, int, int, int],
    exclusion: tuple[int, int, int, int],
) -> tuple[dict[str, object], list[list[float]]]:
    left, top, right, bottom = body
    body_width = right - left
    body_height = bottom - top
    center_x = (left + right) * 0.5
    analysis_top = max(top - ANALYSIS_TOP_MARGIN, 0)
    faint = strength_map(image, 28, exclusion, analysis_top)
    dense = strength_map(image, 60, exclusion, analysis_top)
    faint_points = nonzero_points(faint)
    dense_points = nonzero_points(dense)

    def bounds(points: list[tuple[int, int, float]]) -> tuple[float, float]:
        if not points:
            return 0.0, 0.0
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        return (max(xs) - min(xs) + 1) / body_width, (bottom - min(ys)) / body_height

    faint_width, faint_height = bounds(faint_points)
    dense_width, dense_height = bounds(dense_points)
    total_energy = sum(point[2] for point in dense_points)
    centroid = (
        sum((bottom - y) / body_height * value for _x, y, value in dense_points)
        / total_energy
        if total_energy
        else 0.0
    )
    metrics: dict[str, object] = {
        "faint_width": round(faint_width, 4),
        "dense_width": round(dense_width, 4),
        "faint_height": round(faint_height, 4),
        "dense_height": round(dense_height, 4),
        "energy_centroid_height": round(centroid, 4),
        "aperture_width": aperture_width(
            dense, center_x, bottom, body_width, body_height
        ),
        "angular_profile": angular_profile(dense, center_x, bottom),
        "horizontal_band_periodicity": horizontal_band_periodicity(dense),
        "horizontal_edge_ratio": horizontal_edge_ratio(dense),
        "silhouette_plateau_ratio": silhouette_plateau_ratio(dense),
        "palette": palette_metrics(image, dense),
        "body_overdraw_fraction": body_overdraw(image, body, 28),
    }
    return metrics, dense


def temporal_delta(first: list[list[float]], second: list[list[float]]) -> float:
    total = 0.0
    count = 0
    for row_a, row_b in zip(first, second):
        for value_a, value_b in zip(row_a, row_b):
            total += abs(value_a - value_b)
            count += 1
    return round(total / max(count, 1), 6)


def mean(values: Iterable[float]) -> float:
    sequence = list(values)
    return round(statistics.fmean(sequence), 6) if sequence else 0.0


def angular_l1(source: dict[str, object], render: dict[str, object]) -> float:
    source_profile = source["angular_profile"]
    render_profile = render["angular_profile"]
    assert isinstance(source_profile, list) and isinstance(render_profile, list)
    return round(
        sum(abs(float(a) - float(b)) for a, b in zip(source_profile, render_profile)),
        6,
    )


def metric_summary(
    source_metrics: list[dict[str, object]], render_metrics: list[dict[str, object]]
) -> dict[str, object]:
    summary: dict[str, object] = {}
    for name in METRIC_NAMES:
        differences = [
            abs(float(render[name]) - float(source[name]))
            for source, render in zip(source_metrics, render_metrics)
        ]
        summary[name] = {
            "mean_absolute_error": mean(differences),
            "per_frame_absolute_error": [round(value, 6) for value in differences],
        }
    summary["angular_profile_l1"] = {
        "mean": mean(
            angular_l1(source, render)
            for source, render in zip(source_metrics, render_metrics)
        ),
        "per_frame": [
            angular_l1(source, render)
            for source, render in zip(source_metrics, render_metrics)
        ],
    }
    palette_distances: list[float] = []
    for source, render in zip(source_metrics, render_metrics):
        source_palette = source["palette"]
        render_palette = render["palette"]
        assert isinstance(source_palette, dict) and isinstance(render_palette, dict)
        channels = list(source_palette["p50"]) + list(source_palette["p90"])
        rendered_channels = list(render_palette["p50"]) + list(render_palette["p90"])
        palette_distances.append(
            sum(abs(float(a) - float(b)) for a, b in zip(channels, rendered_channels))
            / len(channels)
        )
    summary["palette_channel_mae"] = {
        "mean": mean(palette_distances),
        "per_frame": [round(value, 6) for value in palette_distances],
    }
    return summary


def make_sheet(
    sources: list[Image.Image], renders: list[Image.Image], path: Path
) -> None:
    columns = 4
    label_height = 22
    pair_width = sources[0].width * 2
    pair_height = sources[0].height + label_height
    rows = math.ceil(len(sources) / columns)
    sheet = Image.new("RGB", (pair_width * columns, pair_height * rows), "black")
    draw = ImageDraw.Draw(sheet)
    for index, (source, render) in enumerate(zip(sources, renders)):
        origin_x = (index % columns) * pair_width
        origin_y = (index // columns) * pair_height
        sheet.paste(source.convert("RGB"), (origin_x, origin_y + label_height))
        sheet.paste(render.convert("RGB"), (origin_x + source.width, origin_y + label_height))
        draw.text((origin_x + 4, origin_y + 4), f"state {index + 1}: source", fill="white")
        draw.text(
            (origin_x + source.width + 4, origin_y + 4),
            f"state {index + 1}: Road of Nogg",
            fill="white",
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, optimize=True)


def main() -> None:
    args = parse_args()
    measurements = json.loads(args.measurements.read_text(encoding="utf-8"))
    source_size = tuple(measurements["coordinate_contract"]["source_size_px"])
    source_body = tuple(measurements["coordinate_contract"]["character_bounds_px"])
    exclusion = tuple(measurements["coordinate_contract"]["character_exclusion_px"])
    source_images = load_images(args.source)
    render_images = load_images(args.render)
    source_original_sizes = [image.size for image in source_images]
    if len(set(source_original_sizes)) != 1:
        raise ValueError(f"Source frame dimensions disagree: {source_original_sizes}")
    source_images = [
        image
        if image.size == source_size
        else image.resize(source_size, Image.Resampling.BICUBIC)
        for image in source_images
    ]

    render_body_bounds = [detect_render_body(image) for image in render_images]
    registered_renders = [
        register_render(image, body, source_size, source_body)
        for image, body in zip(render_images, render_body_bounds)
    ]
    source_results = [measure_frame(image, source_body, exclusion) for image in source_images]
    render_results = [
        measure_frame(image, source_body, exclusion) for image in registered_renders
    ]
    source_metrics = [result[0] for result in source_results]
    render_metrics = [result[0] for result in render_results]
    source_maps = [result[1] for result in source_results]
    render_maps = [result[1] for result in render_results]
    source_temporal = [
        temporal_delta(source_maps[index - 1], source_maps[index])
        for index in range(1, FRAME_COUNT)
    ]
    render_temporal = [
        temporal_delta(render_maps[index - 1], render_maps[index])
        for index in range(1, FRAME_COUNT)
    ]

    report = {
        "schema_version": 1,
        "authority": measurements["authority"],
        "command_label": args.command_label,
        "registration": {
            "source_size_px": source_size,
            "source_original_sizes_px": source_original_sizes,
            "source_resampling": (
                "none"
                if all(size == source_size for size in source_original_sizes)
                else "bicubic_to_measurement_contract"
            ),
            "source_character_bounds_px": source_body,
            "render_body_bounds_px": render_body_bounds,
            "method": "anisotropic proxy-to-source character bounds, center and feet locked",
        },
        "source_files": [
            {"name": path.name, "sha256": sha256(path)} for path in args.source
        ],
        "render_files": [
            {"name": path.name, "sha256": sha256(path)} for path in args.render
        ],
        "source_metrics": source_metrics,
        "render_metrics": render_metrics,
        "comparison": metric_summary(source_metrics, render_metrics),
        "temporal_delta": {
            "source": source_temporal,
            "render": render_temporal,
            "mean_absolute_error": mean(
                abs(a - b) for a, b in zip(source_temporal, render_temporal)
            ),
        },
        "baseline_verdict": {
            "visual_change_in_this_item": "unchanged",
            "reason": "The baseline pass adds measurement evidence and does not alter aura rendering.",
        },
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    make_sheet(source_images, registered_renders, args.sheet)
    print(f"Wrote report: {args.report}")
    print(f"Wrote paired sheet: {args.sheet}")
    print(json.dumps(report["comparison"], indent=2))


if __name__ == "__main__":
    main()
