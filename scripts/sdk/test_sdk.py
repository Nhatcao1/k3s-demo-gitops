#!/usr/bin/env python3
"""Test an installed he-sdk wheel through normal Python code."""

from __future__ import annotations

import json
import math

from he_sdk import HESession


LEFT = [1.25, -2.0, 3.5, 4.0]
RIGHT = [0.75, 5.0, -1.5, 2.0]
ABSOLUTE_TOLERANCE = 1e-3
RELATIVE_TOLERANCE = 1e-3


def check(
    operation: str,
    observed: list[float] | float,
    expected: list[float] | float,
) -> dict[str, object]:
    observed_values = observed if isinstance(observed, list) else [observed]
    expected_values = expected if isinstance(expected, list) else [expected]

    if len(observed_values) != len(expected_values):
        raise RuntimeError(
            f"{operation}: returned {len(observed_values)} values; "
            f"expected {len(expected_values)}"
        )

    errors = [
        abs(actual - wanted)
        for actual, wanted in zip(
            observed_values,
            expected_values,
            strict=True,
        )
    ]
    passed = all(
        math.isclose(
            actual,
            wanted,
            rel_tol=RELATIVE_TOLERANCE,
            abs_tol=ABSOLUTE_TOLERANCE,
        )
        for actual, wanted in zip(
            observed_values,
            expected_values,
            strict=True,
        )
    )
    result = {
        "operation": operation,
        "observed": observed_values,
        "expected": expected_values,
        "maximum_absolute_error": max(errors),
        "status": "PASS" if passed else "FAIL",
    }
    print(json.dumps(result, sort_keys=True))
    if not passed:
        raise RuntimeError(f"{operation} failed correctness validation")
    return result


def main() -> None:
    mean = sum(LEFT) / len(LEFT)

    with HESession.create(backend="openfhe") as he:
        left = he.encrypt(LEFT)
        right = he.encrypt(RIGHT)

        cases = {
            "add": (
                he.decrypt(he.add(left, right)),
                [a + b for a, b in zip(LEFT, RIGHT, strict=True)],
            ),
            "subtract": (
                he.decrypt(he.subtract(left, right)),
                [a - b for a, b in zip(LEFT, RIGHT, strict=True)],
            ),
            "multiply": (
                he.decrypt(he.multiply(left, right)),
                [a * b for a, b in zip(LEFT, RIGHT, strict=True)],
            ),
            "square": (
                he.decrypt(he.square(left)),
                [value * value for value in LEFT],
            ),
            "sum": (
                he.decrypt(he.sum(left)),
                sum(LEFT),
            ),
            "mean": (
                he.decrypt(he.mean(left)),
                mean,
            ),
            "variance": (
                he.decrypt(he.variance(left)),
                sum((value - mean) ** 2 for value in LEFT) / len(LEFT),
            ),
        }

        for operation, (observed, expected) in cases.items():
            check(operation, observed, expected)

    print("SDK_PYTHON_TEST=PASS")


if __name__ == "__main__":
    main()
