from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
CLIENT_DIR = REPO_ROOT / "scripts" / "evaluate-api"
sys.path.insert(0, str(CLIENT_DIR))

from evaluate_test_common import build_request, expected_values  # noqa: E402


class EvaluateApiFunctionalTests(unittest.TestCase):
    def test_each_operation_has_its_own_python_and_shell_file(self) -> None:
        for operation in (
            "add",
            "subtract",
            "multiply",
            "square",
            "sum",
            "mean",
            "variance",
        ):
            self.assertTrue((CLIENT_DIR / f"test_{operation}.py").is_file())
            self.assertTrue((CLIENT_DIR / f"{operation}.sh").is_file())

    def test_plaintext_oracles(self) -> None:
        self.assertEqual(expected_values("add"), [2.0, 3.0, 2.0, 6.0])
        self.assertEqual(expected_values("multiply"), [0.9375, -10.0, -5.25, 8.0])
        self.assertEqual(expected_values("sum"), [6.75])
        self.assertEqual(expected_values("mean"), [1.6875])

    def test_cpu_add_payload_has_ciphertexts_but_no_public_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("context.bin", "ciphertext-a.bin", "ciphertext-b.bin"):
                (root / name).write_bytes(name.encode("ascii"))
            payload = build_request("add", root, False)
        self.assertIn("ciphertext_b", payload)
        self.assertNotIn("public_key", payload)
        self.assertNotIn("evaluation_keys", payload)

    def test_gpu_variance_payload_has_public_and_both_eval_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in (
                "context.bin",
                "public-key.bin",
                "ciphertext-a.bin",
                "multiplication-keys.bin",
                "rotation-keys.bin",
            ):
                (root / name).write_bytes(name.encode("ascii"))
            payload = build_request("variance", root, True)
        self.assertIn("public_key", payload)
        self.assertIn("multiplication_keys", payload)
        self.assertIn("rotation_keys", payload)
        self.assertEqual(payload["valid_count"], 4)
        self.assertNotIn("ciphertext_b", payload)


if __name__ == "__main__":
    unittest.main()
