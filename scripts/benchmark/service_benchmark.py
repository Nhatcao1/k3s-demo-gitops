#!/usr/bin/env python3
"""Benchmark the deployed OpenFHE service against matching Python operations."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
from statistics import median
import tempfile
import time
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PRIMITIVE_OPERATIONS = ("add", "subtract", "multiply")
OPERATIONS = PRIMITIVE_OPERATIONS + ("sum", "variance")
REDUCTION_OPERATIONS = ("sum", "variance")


def _fides_sum_rotation_indices(valid_count: int) -> list[int]:
    """Keys required by FIDESlib Accumulate(..., bStep=4)."""
    indices: list[int] = []
    step = 1
    while step < valid_count:
        for multiplier in range(1, 4):
            index = multiplier * step
            if index < valid_count:
                indices.append(index)
        step *= 4
    return indices


def _timed(function: Callable[..., Any], *args: Any) -> tuple[Any, float]:
    started = time.perf_counter()
    result = function(*args)
    return result, time.perf_counter() - started


def _serialize(openfhe: Any, path: Path, value: Any) -> bytes:
    if not openfhe.SerializeToFile(str(path), value, openfhe.BINARY):
        raise RuntimeError(f"could not serialize {path.name}")
    return path.read_bytes()


def _encoded(value: bytes) -> str:
    return base64.b64encode(value).decode("ascii")


def _request_json(url: str, payload: dict[str, Any], timeout: float) -> tuple[dict[str, Any], float]:
    request = Request(
        url,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    try:
        with urlopen(request, timeout=timeout) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"service returned HTTP {error.code}: {detail}") from error
    except URLError as error:
        raise RuntimeError(f"could not reach evaluator service: {error}") from error
    return result, time.perf_counter() - started


def _check_capabilities(url: str, timeout: float, operations: tuple[str, ...]) -> dict[str, Any]:
    capabilities_url = url.removesuffix("/v1/evaluate") + "/v1/capabilities"
    try:
        with urlopen(capabilities_url, timeout=timeout) as response:
            payload = json.load(response)
    except (HTTPError, URLError) as error:
        raise RuntimeError(f"evaluator capabilities check failed: {error}") from error
    available = payload.get("operations")
    missing = [operation for operation in operations if operation not in (available or [])]
    if missing:
        raise RuntimeError(f"evaluator does not advertise operations: {missing}")
    return payload


def _values(start: int, count: int) -> tuple[list[float], list[float]]:
    """Create bounded deterministic inputs without holding the full matrix."""
    left = [((index % 97) - 48) / 16.0 for index in range(start, start + count)]
    right = [((index % 89) - 44) / 17.0 for index in range(start, start + count)]
    return left, right


def _python_operation(operation: str, left: list[float], right: list[float]) -> list[float] | float:
    if operation == "add":
        return [a + b for a, b in zip(left, right)]
    if operation == "subtract":
        return [a - b for a, b in zip(left, right)]
    if operation == "multiply":
        return [a * b for a, b in zip(left, right)]
    if operation == "sum":
        return sum(left)
    if operation == "variance":
        mean = sum(left) / len(left)
        return sum((value - mean) ** 2 for value in left) / len(left)
    raise ValueError(f"unsupported operation: {operation}")


def _error(observed: list[float] | float, expected: list[float] | float) -> tuple[float, float]:
    if isinstance(expected, list):
        if not isinstance(observed, list) or len(observed) != len(expected):
            raise RuntimeError("decrypted vector shape does not match Python baseline")
        pairs = zip(observed, expected)
    else:
        if isinstance(observed, list):
            raise RuntimeError("decrypted reduction result is not a scalar")
        pairs = [(observed, expected)]
    absolute = 0.0
    relative = 0.0
    for actual, wanted in pairs:
        difference = abs(float(actual) - float(wanted))
        absolute = max(absolute, difference)
        relative = max(relative, difference / max(1.0, abs(float(wanted))))
    return absolute, relative


def _create_client(
    openfhe: Any,
    batch_size: int,
    operations: tuple[str, ...],
    public_key_required: bool,
) -> tuple[Any, Any, bytes, bytes | None, dict[str, bytes], float]:
    started = time.perf_counter()
    parameters = openfhe.CCParamsCKKSRNS()
    parameters.SetMultiplicativeDepth(2 if "variance" in operations else 1)
    parameters.SetScalingModSize(50)
    parameters.SetBatchSize(batch_size)
    context = openfhe.GenCryptoContext(parameters)
    for feature in (
        openfhe.PKE,
        openfhe.KEYSWITCH,
        openfhe.LEVELEDSHE,
        openfhe.ADVANCEDSHE,
    ):
        context.Enable(feature)
    keys = context.KeyGen()
    if "multiply" in operations or "variance" in operations:
        context.EvalMultKeyGen(keys.secretKey)
    if "sum" in operations or "variance" in operations:
        context.EvalSumKeyGen(keys.secretKey)
        if public_key_required:
            context.EvalRotateKeyGen(
                keys.secretKey, _fides_sum_rotation_indices(batch_size)
            )

    with tempfile.TemporaryDirectory(prefix="he-service-setup-") as directory:
        root = Path(directory)
        context_bytes = _serialize(openfhe, root / "context.bin", context)
        public_key_bytes = None
        if public_key_required:
            public_key_bytes = _serialize(
                openfhe, root / "public-key.bin", keys.publicKey
            )
        evaluation_keys: dict[str, bytes] = {}
        if "multiply" in operations or "variance" in operations:
            path = root / "eval-mult.bin"
            if not context.SerializeEvalMultKey(str(path), openfhe.BINARY):
                raise RuntimeError("could not serialize multiplication keys")
            evaluation_keys["multiplication"] = path.read_bytes()
        if "sum" in operations or "variance" in operations:
            path = root / "eval-sum.bin"
            if not context.SerializeEvalAutomorphismKey(str(path), openfhe.BINARY):
                raise RuntimeError("could not serialize SUM keys")
            evaluation_keys["rotation"] = path.read_bytes()
    return (
        context,
        keys,
        context_bytes,
        public_key_bytes,
        evaluation_keys,
        time.perf_counter() - started,
    )


def _run_operation(
    *,
    openfhe: Any,
    operation: str,
    url: str,
    value_count: int,
    batch_size: int,
    repetitions: int,
    timeout: float,
    absolute_tolerance: float,
    relative_tolerance: float,
    context: Any,
    keys: Any,
    context_bytes: bytes,
    public_key_bytes: bytes | None,
    evaluation_keys: dict[str, bytes],
) -> dict[str, Any]:
    context_encoded = _encoded(context_bytes)
    rows: list[dict[str, Any]] = []

    with tempfile.TemporaryDirectory(prefix=f"he-service-{operation}-") as directory:
        root = Path(directory)
        for repetition in range(1, repetitions + 1):
            totals = {
                "python_seconds": 0.0,
                "client_encrypt_seconds": 0.0,
                "client_serialize_seconds": 0.0,
                "service_roundtrip_seconds": 0.0,
                "service_evaluation_seconds": 0.0,
                "client_decrypt_seconds": 0.0,
            }
            maximum_absolute_error = 0.0
            maximum_relative_error = 0.0
            expected_total = 0.0
            observed_total = 0.0
            chunks = 0

            for start in range(0, value_count, batch_size):
                count = min(batch_size, value_count - start)
                left, right = _values(start, count)
                expected, elapsed = _timed(_python_operation, operation, left, right)
                totals["python_seconds"] += elapsed

                encryption_started = time.perf_counter()
                left_plaintext = context.MakeCKKSPackedPlaintext(left)
                left_ciphertext = context.Encrypt(keys.publicKey, left_plaintext)
                right_ciphertext = None
                if operation in PRIMITIVE_OPERATIONS:
                    right_plaintext = context.MakeCKKSPackedPlaintext(right)
                    right_ciphertext = context.Encrypt(keys.publicKey, right_plaintext)
                totals["client_encrypt_seconds"] += time.perf_counter() - encryption_started

                serialization_started = time.perf_counter()
                left_bytes = _serialize(openfhe, root / "left.bin", left_ciphertext)
                payload: dict[str, Any] = {
                    "operation": operation,
                    "context": context_encoded,
                    "ciphertext_a": _encoded(left_bytes),
                    "request_id": f"{operation}-{repetition}-{chunks}",
                }
                if public_key_bytes is not None:
                    payload["public_key"] = _encoded(public_key_bytes)
                if right_ciphertext is not None:
                    right_bytes = _serialize(openfhe, root / "right.bin", right_ciphertext)
                    payload["ciphertext_b"] = _encoded(right_bytes)
                if operation == "multiply":
                    payload["evaluation_keys"] = _encoded(
                        evaluation_keys["multiplication"]
                    )
                elif operation == "sum":
                    payload["evaluation_keys"] = _encoded(
                        evaluation_keys["rotation"]
                    )
                elif operation == "variance":
                    payload["multiplication_keys"] = _encoded(
                        evaluation_keys["multiplication"]
                    )
                    payload["rotation_keys"] = _encoded(
                        evaluation_keys["rotation"]
                    )
                if operation in REDUCTION_OPERATIONS:
                    payload["valid_count"] = count
                totals["client_serialize_seconds"] += time.perf_counter() - serialization_started

                response, elapsed = _request_json(url, payload, timeout)
                totals["service_roundtrip_seconds"] += elapsed
                totals["service_evaluation_seconds"] += float(
                    response.get("evaluation_seconds", 0.0)
                )

                decrypt_started = time.perf_counter()
                encoded_result = response.get("ciphertext")
                if not isinstance(encoded_result, str):
                    raise RuntimeError("service response has no ciphertext")
                result_path = root / "result.bin"
                result_path.write_bytes(base64.b64decode(encoded_result, validate=True))
                result_ciphertext, ok = openfhe.DeserializeCiphertext(
                    str(result_path), openfhe.BINARY
                )
                if not ok:
                    raise RuntimeError("could not deserialize result ciphertext")
                plaintext = context.Decrypt(keys.secretKey, result_ciphertext)
                output_length = 1 if operation in REDUCTION_OPERATIONS else count
                plaintext.SetLength(output_length)
                values = [float(value) for value in plaintext.GetRealPackedValue()[:output_length]]
                observed: list[float] | float = (
                    values[0] if operation in REDUCTION_OPERATIONS else values
                )
                totals["client_decrypt_seconds"] += time.perf_counter() - decrypt_started

                absolute_error, relative_error = _error(observed, expected)
                maximum_absolute_error = max(maximum_absolute_error, absolute_error)
                maximum_relative_error = max(maximum_relative_error, relative_error)
                if operation == "sum":
                    expected_total += float(expected)
                    observed_total += float(observed)
                chunks += 1

            end_to_end = (
                totals["client_encrypt_seconds"]
                + totals["client_serialize_seconds"]
                + totals["service_roundtrip_seconds"]
                + totals["client_decrypt_seconds"]
            )
            if operation == "sum":
                global_absolute_error = abs(observed_total - expected_total)
                global_relative_error = global_absolute_error / max(
                    1.0, abs(expected_total)
                )
                maximum_absolute_error = max(
                    maximum_absolute_error, global_absolute_error
                )
                maximum_relative_error = max(
                    maximum_relative_error, global_relative_error
                )
            passed = (
                maximum_absolute_error <= absolute_tolerance
                or maximum_relative_error <= relative_tolerance
            )
            row = {
                "repetition": repetition,
                "chunks": chunks,
                **totals,
                "end_to_end_seconds": end_to_end,
                "slowdown_vs_python": end_to_end / max(totals["python_seconds"], 1e-12),
                "values_per_second": value_count / max(end_to_end, 1e-12),
                "maximum_absolute_error": maximum_absolute_error,
                "maximum_relative_error": maximum_relative_error,
                "status": "PASS" if passed else "FAIL",
            }
            if operation == "sum":
                row["python_total"] = expected_total
                row["decrypted_total"] = observed_total
            rows.append(row)

    metric_names = (
        "python_seconds",
        "client_encrypt_seconds",
        "client_serialize_seconds",
        "service_roundtrip_seconds",
        "service_evaluation_seconds",
        "client_decrypt_seconds",
        "end_to_end_seconds",
        "slowdown_vs_python",
        "values_per_second",
    )
    medians = {
        name: median(float(row[name]) for row in rows)
        for name in metric_names
    }
    return {
        "operation": operation,
        "status": "PASS" if all(row["status"] == "PASS" for row in rows) else "FAIL",
        "value_count": value_count,
        "batch_size": batch_size,
        "chunks": rows[0]["chunks"],
        "repetitions": repetitions,
        "median": medians,
        "maximum_absolute_error": max(float(row["maximum_absolute_error"]) for row in rows),
        "maximum_relative_error": max(float(row["maximum_relative_error"]) for row in rows),
        "runs": rows,
    }


def run_benchmark(args: argparse.Namespace) -> dict[str, Any]:
    try:
        import openfhe
    except ImportError as error:
        raise RuntimeError("OpenFHE-Python is required in the benchmark client") from error

    operations = (
        PRIMITIVE_OPERATIONS if args.workload == "primitive"
        else (args.workload,)
    )
    capabilities = _check_capabilities(args.url, args.timeout, operations)
    public_key_required = bool(capabilities.get("public_key_required_by_api", False))
    (
        context,
        keys,
        context_bytes,
        public_key_bytes,
        evaluation_keys,
        setup_seconds,
    ) = _create_client(
        openfhe, args.batch_size, operations, public_key_required
    )
    results = [
        _run_operation(
            openfhe=openfhe,
            operation=operation,
            url=args.url,
            value_count=args.value_count,
            batch_size=args.batch_size,
            repetitions=args.repetitions,
            timeout=args.timeout,
            absolute_tolerance=args.absolute_tolerance,
            relative_tolerance=args.relative_tolerance,
            context=context,
            keys=keys,
            context_bytes=context_bytes,
            public_key_bytes=public_key_bytes,
            evaluation_keys=evaluation_keys,
        )
        for operation in operations
    ]
    return {
        "status": "PASS" if all(result["status"] == "PASS" for result in results) else "FAIL",
        "benchmark": "deployed OpenFHE service versus Python baseline",
        "service_url": args.url,
        "backend": capabilities.get("backend"),
        "workload": args.workload,
        "value_count": args.value_count,
        "batch_size": args.batch_size,
        "repetitions": args.repetitions,
        "context_and_key_setup_seconds": setup_seconds,
        "secret_key_sent_to_service": False,
        "public_key_sent_to_service": public_key_required,
        "operations": results,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://he-evaluator:8080/v1/evaluate")
    parser.add_argument(
        "--workload", choices=("primitive", "sum", "variance"), required=True
    )
    parser.add_argument("--value-count", type=int, required=True)
    parser.add_argument("--batch-size", type=int, default=8192)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("--absolute-tolerance", type=float, default=1e-3)
    parser.add_argument("--relative-tolerance", type=float, default=1e-6)
    args = parser.parse_args()
    if args.value_count < 1:
        parser.error("--value-count must be positive")
    if args.batch_size < 2:
        parser.error("--batch-size must be at least two")
    if args.batch_size & (args.batch_size - 1):
        parser.error("--batch-size must be a power of two")
    if args.repetitions < 1:
        parser.error("--repetitions must be positive")
    result = run_benchmark(args)
    print("BENCHMARK_RESULT=" + json.dumps(result, separators=(",", ":")))
    if result["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
