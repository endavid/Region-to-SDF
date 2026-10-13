import math
import json
from pathlib import Path
import unittest

import numpy as np
from PIL import Image

from density_df import classify_regions, compute_distance_field, densityAndDistanceFieldImage


class DensityDFTests(unittest.TestCase):
    def test_sample_matches_macos_app_pixel_for_pixel(self):
        scripts = Path(__file__).resolve().parent
        pictures = scripts.parent / "Pictures"
        config = json.loads((scripts / "regions.example.json").read_text())
        with Image.open(pictures / "RegionTest128x128.png") as source:
            rgb = np.asarray(source.convert("RGB"))
        with Image.open(pictures / "RegionTest128x128_DF_expectation.png") as source:
            expected = np.asarray(source.convert("RGBA"))
        np.testing.assert_array_equal(densityAndDistanceFieldImage(rgb, config), expected)

    def test_image_edges_are_boundaries(self):
        actual = compute_distance_field(np.zeros((5, 5), dtype=int))
        np.testing.assert_array_equal(actual, [
            [1, 1, 1, 1, 1], [1, 2, 2, 2, 1],
            [1, 2, 3, 2, 1], [1, 2, 2, 2, 1], [1, 1, 1, 1, 1],
        ])

    def test_diagonal_boundary_and_propagation(self):
        labels = np.zeros((11, 11), dtype=int)
        labels[5, 5] = 1
        distances = compute_distance_field(labels)
        self.assertEqual(distances[4, 4], np.float32(math.sqrt(2)))
        self.assertEqual(distances[3, 3], np.float32(2) * np.float32(math.sqrt(2)))
        self.assertEqual(distances[5, 5], 1)

    def test_tolerance_overrides_ties_and_nearest(self):
        config = {"epsilon": 1, "regions": [
            {"color": [10, 0, 0]}, {"color": [14, 0, 0], "epsilon": 3},
        ]}
        rgb = np.array([[[11, 0, 0], [12, 0, 0], [255, 0, 0]]])
        np.testing.assert_array_equal(classify_regions(rgb, config), [[0, 1, -1]])
        np.testing.assert_array_equal(classify_regions(rgb, config, True), [[0, 0, 1]])

    def test_regional_normalization_and_unmatched_output(self):
        rgb = np.zeros((7, 10, 3), dtype=np.uint8)
        rgb[:, :7] = [255, 0, 0]
        rgb[:, 7:9] = [0, 255, 0]
        config = {"epsilon": 0, "regions": [
            {"color": "#FF0000"}, {"color": "#00FF00"},
        ]}
        image = densityAndDistanceFieldImage(rgb, config)
        np.testing.assert_array_equal(image[3, 3], [255, 102, 0, 255])
        np.testing.assert_array_equal(image[3, 7], [255, 26, 0, 255])
        np.testing.assert_array_equal(image[3, 9], [0, 0, 0, 255])


if __name__ == "__main__":
    unittest.main()
