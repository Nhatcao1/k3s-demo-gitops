from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
COMPARE_DIR = REPO_ROOT / "scripts" / "benchmark" / "compare"
sys.path.insert(0, str(COMPARE_DIR))

from data_profiles import (  # noqa: E402
    RANDOM_DATA_PROFILES,
    SEQUENTIAL_DATA_PROFILES,
    expand_profiles,
    values,
)
from generate_data import generate_profile  # noqa: E402
from compare_operations import parse_args  # noqa: E402


class SequentialStressDataTests(unittest.TestCase):
    def test_positive_and_negative_profiles_repeat_exact_bound(self) -> None:
        positive = list(
            values("sequential_positive_integer", 40_002, 42, "a")
        )
        negative = list(
            values("sequential_negative_integer", 40_002, 42, "b")
        )

        self.assertEqual(positive[:3], [1.0, 2.0, 3.0])
        self.assertEqual(positive[39_999:], [40_000.0, 1.0, 2.0])
        self.assertEqual(negative[:3], [-1.0, -2.0, -3.0])
        self.assertEqual(negative[39_999:], [-40_000.0, -1.0, -2.0])

    def test_original_all_and_new_stress_groups_are_separate(self) -> None:
        self.assertEqual(expand_profiles(["all"]), list(RANDOM_DATA_PROFILES))
        self.assertEqual(
            expand_profiles(["stress"]),
            list(SEQUENTIAL_DATA_PROFILES),
        )

    def test_generator_records_cyclic_sequence_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            metadata = generate_profile(
                Path(directory),
                "sequential_positive_integer",
                40_002,
                42,
                False,
            )

            self.assertEqual(
                metadata["source"], "deterministic_cyclic_sequence_csv"
            )
            self.assertEqual(metadata["sequence_period"], 40_000)
            rows = (
                Path(directory) / "sequential_positive_integer.csv"
            ).read_text(encoding="utf-8").splitlines()
            self.assertEqual(rows[1], "1,1")
            self.assertEqual(rows[40_000], "40000,40000")
            self.assertEqual(rows[40_001], "1,1")

    def test_decimal_stress_uses_seeded_fractional_digits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            metadata = generate_profile(
                Path(directory),
                "sequential_positive_decimal_6",
                40_001,
                42,
                False,
            )

            self.assertEqual(
                metadata["fraction_source"],
                "deterministic_seeded_random_digits",
            )
            rows = (
                Path(directory) / "sequential_positive_decimal_6.csv"
            ).read_text(encoding="utf-8").splitlines()
            first_a, first_b = rows[1].split(",")
            self.assertTrue(first_a.startswith("1."))
            self.assertTrue(first_b.startswith("1."))
            self.assertEqual(len(first_a.split(".")[1]), 6)
            self.assertEqual(len(first_b.split(".")[1]), 6)
            self.assertNotEqual(first_a, first_b)
            self.assertNotEqual(first_a[-1], "0")
            self.assertNotEqual(first_b[-1], "0")
            self.assertEqual(rows[40_000], "40000.000000,40000.000000")
            self.assertTrue(rows[40_001].startswith("1."))


class FailureExtractionTests(unittest.TestCase):
    def test_hard_oom_records_last_attempt(self) -> None:
        attempt = {
            "data_profile": "sequential_positive_integer",
            "value_count": 5_000_000,
            "operation": "add",
            "backend": "cpu",
            "repetition": 1,
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "job.log"
            output = root / "result"
            log.write_text(
                "HE_COMPARISON_ATTEMPT="
                + json.dumps(attempt, separators=(",", ":"))
                + "\nReason: OOMKilled\n",
                encoding="utf-8",
            )

            subprocess.run(
                [
                    sys.executable,
                    str(COMPARE_DIR / "extract_result.py"),
                    str(log),
                    str(output),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            result = json.loads(
                (output / "result.json").read_text(encoding="utf-8")
            )
            self.assertFalse(result["run_completed"])
            self.assertEqual(result["failures"][0]["error_type"], "OOMKilled")
            self.assertEqual(result["failures"][0]["value_count"], 5_000_000)
            self.assertTrue((output / "failures.csv").is_file())
            self.assertFalse((output / "summary.csv").exists())


class ComparisonArgumentTests(unittest.TestCase):
    def test_size_has_no_artificial_upper_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = [
                "compare_operations.py",
                "--sizes",
                "100000000000",
                "--data-dir",
                directory,
            ]
            with mock.patch.object(sys, "argv", arguments):
                parsed = parse_args()

        self.assertEqual(parsed.sizes, [100_000_000_000])


if __name__ == "__main__":
    unittest.main()
