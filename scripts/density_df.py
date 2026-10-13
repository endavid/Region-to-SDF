#!/usr/bin/env python3
"""Port of MultiRegionalDF.computeDF / densityAndDistanceFieldImage."""

import argparse
import heapq
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


NEIGHBORS = [
    (-1, 0, np.float32(1)), (1, 0, np.float32(1)),
    (0, -1, np.float32(1)), (0, 1, np.float32(1)),
    (-1, -1, np.float32(math.sqrt(2))), (1, -1, np.float32(math.sqrt(2))),
    (-1, 1, np.float32(math.sqrt(2))), (1, 1, np.float32(math.sqrt(2))),
]


def parse_color(value):
    """Accept #RRGGBB or three integer channels in 0..255."""
    if isinstance(value, str):
        value = value.removeprefix("#")
        if len(value) != 6:
            raise ValueError("hex colors must contain six digits")
        value = [int(value[i:i + 2], 16) for i in (0, 2, 4)]
    if not isinstance(value, list) or len(value) != 3 or any(
        type(c) is not int or not 0 <= c <= 255 for c in value
    ):
        raise ValueError("color must be #RRGGBB or [r, g, b] integers in 0..255")
    return np.asarray(value, dtype=np.float32)


def classify_regions(rgb, config, nearest=False):
    """Nearest eligible RGB color wins; ties use JSON order. -1 is background."""
    matching = config.get("matching", "tolerance")
    if matching not in ("nearest", "tolerance"):
        raise ValueError("matching must be 'nearest' or 'tolerance'")
    nearest = nearest or matching == "nearest"
    entries = config.get("regions")
    if not isinstance(entries, list) or not entries:
        raise ValueError("config must contain a nonempty regions list")
    pixels = np.asarray(rgb, dtype=np.float32)
    labels = np.full(pixels.shape[:2], -1, dtype=np.int32)
    best = np.full(labels.shape, np.inf, dtype=np.float32)
    for i, entry in enumerate(entries):
        color = parse_color(entry["color"])
        epsilon = float(entry.get("epsilon", config.get("epsilon", 5)))
        if not math.isfinite(epsilon) or epsilon < 0:
            raise ValueError("epsilon must be finite and nonnegative")
        difference = np.sum((pixels - color) ** 2, axis=2)
        eligible = np.ones(labels.shape, dtype=bool) if nearest else difference <= epsilon ** 2
        choose = eligible & (difference < best)
        labels[choose] = i
        best[choose] = difference[choose]
    return labels


def compute_distance_field(labels):
    """Swift's multi-source Dijkstra, including exterior image boundaries.

    Boundary pixels start at 1 (or sqrt(2) for diagonal-only boundaries).
    Propagation is unrestricted across labels, as in the app. Float32
    additions reproduce Swift Float arithmetic.
    """
    labels = np.asarray(labels)
    if labels.ndim != 2 or not labels.size:
        raise ValueError("labels must be a nonempty 2D array")
    height, width = labels.shape
    distances = np.full(labels.shape, np.float32(1e10), dtype=np.float32)
    # Vectorized boundary initialization avoids a Python scan per neighbor.
    padded = np.pad(labels, 1, mode="constant", constant_values=-2)
    for dx, dy, cost in NEIGHBORS:
        other = padded[1 + dy:1 + dy + height, 1 + dx:1 + dx + width]
        changed = other != labels
        distances[changed] = np.minimum(distances[changed], cost)
    ys, xs = np.nonzero(distances < np.float32(1e10))
    queue = [(float(distances[y, x]), int(y), int(x)) for y, x in zip(ys, xs)]
    heapq.heapify(queue)
    while queue:
        distance, y, x = heapq.heappop(queue)
        if distance > distances[y, x]:
            continue
        for dx, dy, cost in NEIGHBORS:
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height:
                candidate = np.float32(distance) + cost
                if candidate < distances[ny, nx]:
                    distances[ny, nx] = candidate
                    heapq.heappush(queue, (float(candidate), ny, nx))
    return distances


def densityAndDistanceFieldImage(rgb, config, nearest=False):
    """Return uint8 RGBA: regional density, distance/width, zero, opaque.

    Disconnected areas of the same color share one normalization maximum.
    Unmatched pixels contribute boundaries but are black in the output.
    Input alpha is ignored, matching the app's RGB color comparison.
    Set config['matching'] to 'nearest' to reproduce the app's assignment;
    otherwise colors must fall within epsilon of a configured region.
    """
    labels = classify_regions(rgb, config, nearest)
    distances = compute_distance_field(labels)
    maxima = np.zeros(len(config["regions"]), dtype=np.float32)
    matched = labels >= 0
    np.maximum.at(maxima, labels[matched], distances[matched])
    density = np.zeros(labels.shape, dtype=np.float32)
    density[matched] = distances[matched] / maxima[labels[matched]]
    output = np.zeros((*labels.shape, 4), dtype=np.uint8)
    # Swift roundf rounds positive half values up, unlike numpy.rint.
    output[..., 0] = np.floor(np.clip(density, 0, 1) * np.float32(255) + np.float32(0.5))
    green = np.clip(distances / np.float32(labels.shape[1]), 0, 1)
    output[..., 1][matched] = np.floor(green[matched] * np.float32(255) + np.float32(0.5))
    output[..., 3] = 255
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("regions", type=Path, help="JSON region colors and epsilon")
    parser.add_argument("output", type=Path, help="output PNG")
    parser.add_argument("--nearest", action="store_true", help="assign every pixel to its nearest color, like the app; ignore epsilon")
    args = parser.parse_args()
    try:
        config = json.loads(args.regions.read_text())
        with Image.open(args.input) as source:
            rgb = np.asarray(source.convert("RGB"))
        result = densityAndDistanceFieldImage(rgb, config, args.nearest)
        Image.fromarray(result).save(args.output, format="PNG")
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
