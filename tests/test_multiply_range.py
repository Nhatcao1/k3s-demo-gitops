from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
BENCHMARK_DIR = REPO_ROOT / "scripts" / "benchmark" / "multiply-range"
sys.path.insert(0, str(BENCHMARK_DIR))

from multiply_range import (  # noqa: E402
    parse_args,
    run_backend,
    tolerance_passes,
)


class MultiplyRangeTests(unittest.TestCase):
    def test_relative_tolerance_can_pass_large_ckks_value(self) -> None:
        self.assertTrue(tolerance_passes(1.0, 1e-9, 0.1, 1e-6))
        self.assertFalse(tolerance_passes(1.0, 1e-3, 0.1, 1e-6))

    def test_bgv_defaults_to_exact_cpu_only(self) -> None:
        with mock.patch.object(
            sys,
            "argv",
            ["multiply_range.py", "--scheme", "BGV", "--max-factor", "10"],
        ):
            parsed = parse_args()
        self.assertEqual(parsed.backends, ["cpu"])
        self.assertEqual(parsed.abs_tolerance, 0.0)
        self.assertEqual(parsed.rel_tolerance, 0.0)

    def test_range_is_chunked_and_checkpointed_without_dataset(self) -> None:
        def fake_post(
            _url: str, payload: dict[str, object], _timeout: float
        ) -> tuple[dict[str, object], float]:
            left = payload["values_a"]
            right = payload["values_b"]
            assert isinstance(left, list)
            assert isinstance(right, list)
            values = [a * b for a, b in zip(left, right)]
            return (
                {
                    "values": values,
                    "timings": {
                        "context_keygen_seconds": 0.1,
                        "encrypt_seconds": 0.1,
                        "calculation_seconds": 0.1,
                        "decrypt_seconds": 0.1,
                        "total_seconds": 0.4,
                    },
                },
                0.5,
            )

        with mock.patch("multiply_range.post_json", side_effect=fake_post):
            cases = run_backend(
                "cpu", "http://cpu", "CKKS", 2, 2, 10, 3, 5, 10.0, 0.1, 1e-6
            )

        self.assertEqual(
            [(row["factor_start"], row["factor_end"]) for row in cases],
            [(2, 6), (7, 10)],
        )
        self.assertTrue(all(row["accuracy_passed"] for row in cases))

    def test_extractor_keeps_accuracy_failure(self) -> None:
        failure = {
            "scheme": "CKKS",
            "backend": "gpu",
            "base": 2,
            "factor": 100,
            "failure_type": "accuracy_limit",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "job.log"
            output = root / "result"
            log.write_text(
                "HE_MULTIPLY_RANGE_FAILURE="
                + json.dumps(failure, separators=(",", ":"))
                + "\n",
                encoding="utf-8",
            )
            subprocess.run(
                [
                    sys.executable,
                    str(BENCHMARK_DIR / "extract_result.py"),
                    str(log),
                    str(output),
                ],
                check=True,
            )
            result = json.loads(
                (output / "result.json").read_text(encoding="utf-8")
            )
            self.assertEqual(result["failures"], [failure])


if __name__ == "__main__":
    unittest.main()
