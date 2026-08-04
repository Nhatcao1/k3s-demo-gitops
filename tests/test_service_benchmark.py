from __future__ import annotations

from pathlib import Path
import sys
import unittest


BENCHMARK_DIR = Path(__file__).resolve().parents[1] / "scripts" / "benchmark"
sys.path.insert(0, str(BENCHMARK_DIR))

import service_benchmark as benchmark  # noqa: E402


class ServiceBenchmarkTests(unittest.TestCase):
    def test_deterministic_values_continue_across_chunks(self) -> None:
        first_left, first_right = benchmark._values(0, 8)
        next_left, next_right = benchmark._values(8, 4)
        all_left, all_right = benchmark._values(0, 12)
        self.assertEqual(first_left + next_left, all_left)
        self.assertEqual(first_right + next_right, all_right)

    def test_python_operations(self) -> None:
        left = [1.0, 2.0, 3.0]
        right = [4.0, 5.0, 6.0]
        self.assertEqual(benchmark._python_operation("add", left, right), [5.0, 7.0, 9.0])
        self.assertEqual(benchmark._python_operation("subtract", left, right), [-3.0] * 3)
        self.assertEqual(benchmark._python_operation("multiply", left, right), [4.0, 10.0, 18.0])
        self.assertEqual(benchmark._python_operation("sum", left, right), 6.0)

    def test_error_supports_vectors_and_sum_scalars(self) -> None:
        self.assertEqual(benchmark._error([1.0, 2.0], [1.0, 2.0]), (0.0, 0.0))
        absolute, relative = benchmark._error(10.001, 10.0)
        self.assertAlmostEqual(absolute, 0.001)
        self.assertAlmostEqual(relative, 0.0001)


if __name__ == "__main__":
    unittest.main()
