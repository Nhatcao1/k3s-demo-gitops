#!/usr/bin/env python3
"""Stress HE multiplication across an increasing integer factor range."""

from __future__ import annotations

import argparse
import json
import math
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen


CASE_MARKER = "HE_MULTIPLY_RANGE_CASE="
ATTEMPT_MARKER = "HE_MULTIPLY_RANGE_ATTEMPT="
FAILURE_MARKER = "HE_MULTIPLY_RANGE_FAILURE="
RUN_MARKER = "HE_MULTIPLY_RANGE_RUN="


def endpoint(base_url: str, path: str) -> str:
    parsed = urlsplit(base_url)
    if not parsed.scheme or not parsed.netloc:
        raise ValueError(f"invalid service URL: {base_url}")
    return urlunsplit((parsed.scheme, parsed.netloc, path, "", ""))


def get_json(url: str, timeout: float) -> dict[str, Any]:
    try:
        with urlopen(url, timeout=timeout) as response:
            payload = json.load(response)
    except (HTTPError, URLError, TimeoutError) as error:
        raise RuntimeError(f"GET {url} failed: {error}") from error
    if not isinstance(payload, dict):
        raise RuntimeError(f"GET {url} did not return an object")
    return payload


def post_json(
    url: str, payload: dict[str, Any], timeout: float
) -> tuple[dict[str, Any], float]:
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
        raise RuntimeError(
            f"POST {url} returned HTTP {error.code}: {detail}"
        ) from error
    except (URLError, TimeoutError) as error:
        raise RuntimeError(f"POST {url} failed: {error}") from error
    if not isinstance(result, dict):
        raise RuntimeError("multiply response is not an object")
    return result, time.perf_counter() - started


def check_backend(base_url: str, scheme: str, timeout: float) -> None:
    capabilities = get_json(endpoint(base_url, "/v1/capabilities"), timeout)
    if scheme == "BGV":
        demo_schemes = capabilities.get("demo_schemes")
        if not isinstance(demo_schemes, list) or "BGV" not in demo_schemes:
            raise RuntimeError(f"{base_url} does not advertise a BGV demo")
        if capabilities.get("bgv_demo_endpoint") != "/v1/demo/bgv/evaluate":
            raise RuntimeError(f"{base_url} has no BGV multiplication endpoint")
        operations = capabilities.get("bgv_demo_operations")
        if not isinstance(operations, list) or "multiply" not in operations:
            raise RuntimeError(f"{base_url} has no BGV demo multiply operation")
        return

    advertised_scheme = str(capabilities.get("scheme", "")).upper()
    if advertised_scheme != "CKKS":
        raise RuntimeError(
            f"{base_url} advertises {advertised_scheme or 'no scheme'}, not CKKS"
        )
    operations = capabilities.get("native_demo_operations")
    if not isinstance(operations, list) or "multiply" not in operations:
        raise RuntimeError(f"{base_url} has no demo multiply operation")


def response_values(response: dict[str, Any], expected_count: int) -> list[float]:
    values = response.get("values")
    if not isinstance(values, list) or len(values) != expected_count:
        raise RuntimeError("service returned the wrong number of values")
    converted = [float(value) for value in values]
    if any(not math.isfinite(value) for value in converted):
        raise RuntimeError("service returned a non-finite value")
    return converted


def response_timings(response: dict[str, Any]) -> dict[str, float]:
    timings = response.get("timings")
    if not isinstance(timings, dict):
        raise RuntimeError("service response has no timing breakdown")
    return {
        name: float(timings.get(name, 0.0))
        for name in (
            "context_keygen_seconds",
            "encrypt_seconds",
            "calculation_seconds",
            "decrypt_seconds",
            "total_seconds",
        )
    }


def tolerance_passes(
    absolute_error: float,
    relative_error: float,
    absolute_tolerance: float,
    relative_tolerance: float,
) -> bool:
    return (
        absolute_error <= absolute_tolerance
        or relative_error <= relative_tolerance
    )


def run_backend(
    backend: str,
    base_url: str,
    scheme: str,
    base: int,
    start_factor: int,
    max_factor: int,
    chunk_size: int,
    checkpoint_size: int,
    timeout: float,
    absolute_tolerance: float,
    relative_tolerance: float,
) -> list[dict[str, Any]]:
    path = "/v1/demo/bgv/evaluate" if scheme == "BGV" else "/v1/demo/evaluate"
    url = endpoint(base_url, path)
    cases: list[dict[str, Any]] = []
    checkpoint_start = start_factor
    factor = start_factor
    checkpoint_values = 0
    checkpoint_requests = 0
    checkpoint_round_trip = 0.0
    checkpoint_timings = {
        "context_keygen_seconds": 0.0,
        "encrypt_seconds": 0.0,
        "calculation_seconds": 0.0,
        "decrypt_seconds": 0.0,
        "total_seconds": 0.0,
    }
    maximum_absolute_error = 0.0
    maximum_relative_error = 0.0

    while factor <= max_factor:
        checkpoint_end = checkpoint_start + checkpoint_size - 1
        chunk_end = min(
            factor + chunk_size - 1,
            checkpoint_end,
            max_factor,
        )
        factors = list(range(factor, chunk_end + 1))
        left = [base] * len(factors)
        print(
            f"{backend.upper()} {scheme} base={base} factors={factor}..{chunk_end}",
            flush=True,
        )
        attempt = {
            "scheme": scheme,
            "backend": backend,
            "base": base,
            "factor_start": factor,
            "factor_end": chunk_end,
        }
        print(
            ATTEMPT_MARKER + json.dumps(attempt, separators=(",", ":")),
            flush=True,
        )
        try:
            response, round_trip = post_json(
                url,
                {
                    "operation": "multiply",
                    "values_a": left,
                    "values_b": factors,
                },
                timeout,
            )
            observed = response_values(response, len(factors))
            timings = response_timings(response)
        except Exception as error:
            failure = {
                **attempt,
                "factor": factor,
                "failure_type": "runtime_failure",
                "error_type": type(error).__name__,
                "error_message": str(error)[:1000],
            }
            print(
                FAILURE_MARKER + json.dumps(failure, separators=(",", ":")),
                flush=True,
            )
            raise

        for actual, current_factor in zip(observed, factors):
            expected = float(base * current_factor)
            absolute_error = abs(actual - expected)
            relative_error = absolute_error / max(abs(expected), 1e-12)
            maximum_absolute_error = max(
                maximum_absolute_error, absolute_error
            )
            maximum_relative_error = max(
                maximum_relative_error, relative_error
            )
            if not tolerance_passes(
                absolute_error,
                relative_error,
                absolute_tolerance,
                relative_tolerance,
            ):
                failure = {
                    "scheme": scheme,
                    "backend": backend,
                    "base": base,
                    "factor": current_factor,
                    "expected": expected,
                    "actual": actual,
                    "absolute_error": absolute_error,
                    "relative_error": relative_error,
                    "absolute_tolerance": absolute_tolerance,
                    "relative_tolerance": relative_tolerance,
                    "failure_type": "accuracy_limit",
                    "error_type": "AccuracyThresholdExceeded",
                    "error_message": (
                        f"both {scheme} accuracy tolerances were exceeded"
                    ),
                }
                print(
                    FAILURE_MARKER
                    + json.dumps(failure, separators=(",", ":")),
                    flush=True,
                )
                raise RuntimeError(
                    f"{backend} {scheme} accuracy limit at {base} x {current_factor}"
                )

        checkpoint_values += len(factors)
        checkpoint_requests += 1
        checkpoint_round_trip += round_trip
        for name, value in timings.items():
            checkpoint_timings[name] += value
        factor = chunk_end + 1

        if (
            checkpoint_values >= checkpoint_size
            or factor > max_factor
        ):
            case = {
                "scheme": scheme,
                "backend": backend,
                "base": base,
                "factor_start": checkpoint_start,
                "factor_end": factor - 1,
                "value_count": checkpoint_values,
                "requests": checkpoint_requests,
                "maximum_absolute_error": maximum_absolute_error,
                "maximum_relative_error": maximum_relative_error,
                "accuracy_passed": True,
                "end_to_end_seconds": checkpoint_round_trip,
                **checkpoint_timings,
            }
            print(
                CASE_MARKER + json.dumps(case, separators=(",", ":")),
                flush=True,
            )
            cases.append(case)
            checkpoint_start = factor
            checkpoint_values = 0
            checkpoint_requests = 0
            checkpoint_round_trip = 0.0
            checkpoint_timings = {name: 0.0 for name in checkpoint_timings}
            maximum_absolute_error = 0.0
            maximum_relative_error = 0.0
    return cases


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cpu-url", default="http://he-evaluator:8080")
    parser.add_argument("--gpu-url", default="http://he-evaluator-gpu:8080")
    parser.add_argument("--scheme", type=str.upper, default="CKKS")
    parser.add_argument("--backends", nargs="+")
    parser.add_argument("--bases", type=int, nargs="+", default=[1, 2])
    parser.add_argument("--start-factor", type=int, default=2)
    parser.add_argument("--max-factor", type=int, required=True)
    parser.add_argument("--chunk-size", type=int, default=4096)
    parser.add_argument("--checkpoint-size", type=int, default=100_000)
    parser.add_argument("--timeout", type=float, default=3600.0)
    parser.add_argument("--abs-tolerance", type=float)
    parser.add_argument("--rel-tolerance", type=float)
    args = parser.parse_args()
    if args.scheme not in {"CKKS", "BGV"}:
        parser.error("--scheme accepts only CKKS or BGV")
    if args.backends is None:
        args.backends = ["cpu"] if args.scheme == "BGV" else ["cpu", "gpu"]
    if set(args.backends) - {"cpu", "gpu"}:
        parser.error("--backends accepts only cpu and gpu")
    if args.scheme == "BGV" and args.backends != ["cpu"]:
        parser.error("BGV is CPU-only because the FIDESlib GPU service is CKKS-only")
    if not args.bases or any(base < 1 for base in args.bases):
        parser.error("--bases must contain positive integers")
    if args.start_factor < 1 or args.max_factor < args.start_factor:
        parser.error("factor range must be positive and non-empty")
    if not 1 <= args.chunk_size <= 4096:
        parser.error("--chunk-size must be between 1 and 4096")
    if args.checkpoint_size < 1:
        parser.error("--checkpoint-size must be positive")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.abs_tolerance is None:
        args.abs_tolerance = 0.0 if args.scheme == "BGV" else 0.1
    if args.rel_tolerance is None:
        args.rel_tolerance = 0.0 if args.scheme == "BGV" else 1e-6
    if args.abs_tolerance < 0 or args.rel_tolerance < 0:
        parser.error("tolerances cannot be negative")
    return args


def main() -> None:
    args = parse_args()
    urls = {"cpu": args.cpu_url, "gpu": args.gpu_url}
    for backend in args.backends:
        check_backend(urls[backend], args.scheme, args.timeout)

    completed: list[dict[str, Any]] = []
    for base in args.bases:
        for backend in args.backends:
            completed.extend(
                run_backend(
                    backend,
                    urls[backend],
                    args.scheme,
                    base,
                    args.start_factor,
                    args.max_factor,
                    args.chunk_size,
                    args.checkpoint_size,
                    args.timeout,
                    args.abs_tolerance,
                    args.rel_tolerance,
                )
            )
    run = {
        "scheme": args.scheme,
        "backends": args.backends,
        "bases": args.bases,
        "start_factor": args.start_factor,
        "max_factor": args.max_factor,
        "chunk_size": args.chunk_size,
        "checkpoint_size": args.checkpoint_size,
        "accuracy_passed": True,
        "completed_checkpoints": len(completed),
    }
    print(RUN_MARKER + json.dumps(run, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
