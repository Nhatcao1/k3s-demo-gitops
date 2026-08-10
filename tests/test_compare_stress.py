from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
COMPARE_DIR = REPO_ROOT / "scripts" / "benchmark" / "compare"
sys.path.insert(0, str(COMPARE_DIR))

from data_profiles import (  # noqa: E402
    RANDOM_DATA_PROFILES,
    expand_profiles,
    values,
)
from generate_data import generate_profile  # noqa: E402


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
            ["sequential_positive_integer", "sequential_negative_integer"],
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


if __name__ == "__main__":
    unittest.main()
