#!/usr/bin/env python3
"""Compare Python, CPU OpenFHE, and GPU FIDESlib on identical inputs."""

from __future__ import annotations

import argparse
import json
import math
import random
import statistics
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen


OPERATIONS = ("add", "subtract", "multiply", "square", "sum", "mean", "variance")
BINARY_OPERATIONS = {"add", "subtract", "multiply"}
REDUCTION_OPERATIONS = {"sum", "mean", "variance"}
MARKER = "HE_COMPARISON_RESULT="
INPUT_BOUND = 40_000
DATA_PROFILES: dict[str, tuple[str, int]] = {
    "positive_integer": ("positive", 0),
    "negative_integer": ("negative", 0),
    "positive_decimal_1": ("positive", 1),
    "negative_decimal_1": ("negative", 1),
    "positive_decimal_2": ("positive", 2),
    "negative_decimal_2": ("negative", 2),
    "positive_decimal_3": ("positive", 3),
    "negative_decimal_3": ("negative", 3),
    "positive_decimal_6": ("positive", 6),
    "negative_decimal_6": ("negative", 6),
}


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
        raise RuntimeError(f"GET {url} did not return a JSON object")
    return payload


def post_json(
    url: str, payload: dict[str, Any], timeout: float
) -> tuple[dict[str, Any], float]:
    started = time.perf_counter()
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"POST {url} returned HTTP {error.code}: {detail}") from error
    except (URLError, TimeoutError) as error:
        raise RuntimeError(f"POST {url} failed: {error}") from error
    elapsed = time.perf_counter() - started
    if not isinstance(result, dict):
        raise RuntimeError(f"POST {url} did not return a JSON object")
    return result, elapsed


def wait_ready(base_url: str, timeout: float) -> None:
    ready_url = endpoint(base_url, "/readyz")
    deadline = time.monotonic() + min(timeout, 120.0)
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            if get_json(ready_url, min(timeout, 10.0)).get("status") == "ready":
                return
        except RuntimeError as error:
            last_error = error
        time.sleep(2)
    raise RuntimeError(f"service did not become ready at {ready_url}: {last_error}")


def check_capabilities(base_url: str, operations: list[str], timeout: float) -> None:
    capabilities = get_json(endpoint(base_url, "/v1/capabilities"), timeout)
    supported = capabilities.get("native_demo_operations")
    if not isinstance(supported, list):
        raise RuntimeError(f"{base_url} does not advertise native_demo_operations")
    missing = sorted(set(operations) - set(supported))
    if missing:
        raise RuntimeError(f"{base_url} demo is missing operations: {', '.join(missing)}")
    if "sum" in operations and capabilities.get("demo_sum_endpoint") != "/v1/demo/sum":
        raise RuntimeError(f"{base_url} does not advertise /v1/demo/sum")


def python_operation(
    operation: str, values_a: list[float], values_b: list[float] | None
) -> list[float]:
    if operation == "add":
        assert values_b is not None
        return [left + right for left, right in zip(values_a, values_b)]
    if operation == "subtract":
        assert values_b is not None
        return [left - right for left, right in zip(values_a, values_b)]
    if operation == "multiply":
        assert values_b is not None
        return [left * right for left, right in zip(values_a, values_b)]
    if operation == "square":
        return [value * value for value in values_a]
    total = math.fsum(values_a)
    if operation == "sum":
        return [total]
    mean = total / len(values_a)
    if operation == "mean":
        return [mean]
    if operation == "variance":
        return [math.fsum((value - mean) ** 2 for value in values_a) / len(values_a)]
    raise ValueError(f"unsupported operation: {operation}")


def chunks(values: list[float], chunk_size: int) -> list[list[float]]:
    return [values[start : start + chunk_size] for start in range(0, len(values), chunk_size)]


def generate_values(
    random_source: random.Random,
    count: int,
    profile: str,
) -> list[float]:
    sign, decimal_places = DATA_PROFILES[profile]
    multiplier = -1.0 if sign == "negative" else 1.0
    if decimal_places == 0:
        return [
            multiplier * random_source.randint(1, INPUT_BOUND)
            for _ in range(count)
        ]

    scale = 10**decimal_places
    prefix_limit = 10 ** (decimal_places - 1)
    values: list[float] = []
    for _ in range(count):
        whole = random_source.randrange(INPUT_BOUND)
        fractional_prefix = random_source.randrange(prefix_limit)
        fractional_last_digit = random_source.randint(1, 9)
        fraction = fractional_prefix * 10 + fractional_last_digit
        values.append(multiplier * (whole + fraction / scale))
    return values


def expand_profiles(requested: list[str]) -> list[str]:
    if "all" in requested:
        if requested != ["all"]:
            raise ValueError("use --data-profiles all by itself")
        return list(DATA_PROFILES)
    invalid = sorted(set(requested) - set(DATA_PROFILES))
    if invalid:
        raise ValueError(f"invalid data profiles: {', '.join(invalid)}")
    return list(dict.fromkeys(requested))


def input_metadata(
    profile: str,
    operation: str,
    values_a: list[float],
    values_b: list[float],
    seed: int,
) -> dict[str, Any]:
    sign, decimal_places = DATA_PROFILES[profile]
    actual_minimum = min(values_a)
    actual_maximum = max(values_a)
    if operation in BINARY_OPERATIONS:
        actual_minimum = min(actual_minimum, min(values_b))
        actual_maximum = max(actual_maximum, max(values_b))
    return {
        "data_profile": profile,
        "input_sign": sign,
        "decimal_places": decimal_places,
        "input_bound_min": -INPUT_BOUND,
        "input_bound_max": INPUT_BOUND,
        "input_min": actual_minimum,
        "input_max": actual_maximum,
        "seed": seed,
        "source": "deterministic_profile_generator",
    }


def reference_chunks(
    operation: str,
    values_a: list[float],
    values_b: list[float],
    chunk_size: int,
) -> list[list[float]]:
    if operation == "sum":
        return [python_operation(operation, values_a, None)]
    left_chunks = chunks(values_a, chunk_size)
    right_chunks = chunks(values_b, chunk_size)
    return [
        python_operation(operation, left, right if operation in BINARY_OPERATIONS else None)
        for left, right in zip(left_chunks, right_chunks)
    ]


def maximum_errors(
    observed_chunks: list[list[float]], expected_chunks: list[list[float]]
) -> tuple[float, float]:
    if len(observed_chunks) != len(expected_chunks):
        raise RuntimeError("service returned the wrong number of chunks")
    maximum_absolute = 0.0
    maximum_relative = 0.0
    for observed, expected in zip(observed_chunks, expected_chunks):
        if len(observed) != len(expected):
            raise RuntimeError("service returned the wrong number of values")
        for actual, reference in zip(observed, expected):
            difference = abs(actual - reference)
            maximum_absolute = max(maximum_absolute, difference)
            maximum_relative = max(
                maximum_relative,
                difference / max(abs(reference), 1e-12),
            )
    return maximum_absolute, maximum_relative


def response_values(response: dict[str, Any]) -> list[float]:
    values = response.get("values")
    if not isinstance(values, list) or not values:
        raise RuntimeError("service response has no values")
    result: list[float] = []
    for value in values:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise RuntimeError("service returned a non-numeric value")
        converted = float(value)
        if not math.isfinite(converted):
            raise RuntimeError("service returned a non-finite value")
        result.append(converted)
    return result


def response_metadata(response: dict[str, Any]) -> dict[str, Any]:
    """Keep timings and backend details without copying large result vectors."""
    return {name: value for name, value in response.items() if name != "values"}


def run_python_repetition(
    operation: str,
    values_a: list[float],
    values_b: list[float],
    chunk_size: int,
) -> tuple[float, list[list[float]]]:
    started = time.perf_counter()
    result = reference_chunks(operation, values_a, values_b, chunk_size)
    return time.perf_counter() - started, result


def run_service_repetition(
    base_url: str,
    operation: str,
    values_a: list[float],
    values_b: list[float],
    chunk_size: int,
    sum_request_size: int,
    timeout: float,
) -> tuple[float, float, float | None, list[list[float]], list[dict[str, Any]]]:
    if operation == "sum":
        partial_values: list[float] = []
        responses: list[dict[str, Any]] = []
        service_seconds = 0.0
        round_trip_seconds = 0.0
        he_compute_seconds = 0.0
        for part in chunks(values_a, sum_request_size):
            response, round_trip = post_json(
                endpoint(base_url, "/v1/demo/sum"),
                {"values": part},
                timeout,
            )
            timings = response.get("timings")
            if not isinstance(timings, dict):
                raise RuntimeError("SUM response has no timing breakdown")
            response_result = response_values(response)
            if len(response_result) != 1:
                raise RuntimeError("SUM response must contain one value")
            partial_values.append(response_result[0])
            service_seconds += float(timings.get("total_seconds", round_trip))
            round_trip_seconds += round_trip
            he_compute_seconds += float(timings.get("sum_seconds", 0.0))
            he_compute_seconds += float(timings.get("combine_seconds", 0.0))
            responses.append(response_metadata(response))
        return (
            service_seconds,
            round_trip_seconds,
            he_compute_seconds,
            [[math.fsum(partial_values)]],
            responses,
        )

    observed: list[list[float]] = []
    responses: list[dict[str, Any]] = []
    service_seconds = 0.0
    round_trip_seconds = 0.0
    left_chunks = chunks(values_a, chunk_size)
    right_chunks = chunks(values_b, chunk_size)
    url = endpoint(base_url, "/v1/demo/evaluate")
    for left, right in zip(left_chunks, right_chunks):
        payload: dict[str, Any] = {"operation": operation, "values_a": left}
        if operation in BINARY_OPERATIONS:
            payload["values_b"] = right
        response, round_trip = post_json(url, payload, timeout)
        evaluation_seconds = response.get("evaluation_seconds")
        if not isinstance(evaluation_seconds, (int, float)):
            raise RuntimeError("service response has no evaluation_seconds")
        service_seconds += float(evaluation_seconds)
        round_trip_seconds += round_trip
        observed.append(response_values(response))
        responses.append(response_metadata(response))
    return service_seconds, round_trip_seconds, None, observed, responses


def median_optional(values: list[float | None]) -> float | None:
    materialized = [value for value in values if value is not None]
    return statistics.median(materialized) if materialized else None


def result_scope(
    operation: str, value_count: int, sum_request_size: int
) -> str:
    if operation == "sum":
        return (
            "global_scalar"
            if value_count <= sum_request_size
            else "global_scalar_client_combined"
        )
    if operation in {"mean", "variance"}:
        return "per_chunk_scalar"
    return "elementwise_vector"


def run_benchmark(args: argparse.Namespace) -> dict[str, Any]:
    operations = (
        list(OPERATIONS)
        if args.operations == ["all"]
        else list(dict.fromkeys(args.operations))
    )
    invalid = sorted(set(operations) - set(OPERATIONS))
    if invalid or "all" in operations:
        raise ValueError(f"invalid operations: {', '.join(invalid or operations)}")
    profiles = expand_profiles(args.data_profiles)

    wait_ready(args.cpu_url, args.timeout)
    wait_ready(args.gpu_url, args.timeout)
    check_capabilities(args.cpu_url, operations, args.timeout)
    check_capabilities(args.gpu_url, operations, args.timeout)

    summaries: list[dict[str, Any]] = []
    details: list[dict[str, Any]] = []
    all_passed = True
    maximum_size = max(args.sizes)

    for profile in profiles:
        random_source = random.Random(f"{args.seed}:{profile}")
        all_a = generate_values(random_source, maximum_size, profile)
        all_b = generate_values(random_source, maximum_size, profile)

        for size in sorted(set(args.sizes)):
            values_a = all_a[:size]
            values_b = all_b[:size]
            for operation in operations:
                expected = reference_chunks(
                    operation, values_a, values_b, args.chunk_size
                )
                chunk_count = (
                    math.ceil(size / args.sum_request_size)
                    if operation == "sum"
                    else len(expected)
                )
                metadata = input_metadata(
                    profile, operation, values_a, values_b, args.seed
                )

                python_times: list[float] = []
                for repetition in range(1, args.repetitions + 1):
                    elapsed, observed = run_python_repetition(
                        operation, values_a, values_b, args.chunk_size
                    )
                    absolute, relative = maximum_errors(observed, expected)
                    python_times.append(elapsed)
                    details.append(
                        {
                            "operation": operation,
                            "backend": "python",
                            "value_count": size,
                            "chunks": chunk_count,
                            "repetition": repetition,
                            "service_seconds": elapsed,
                            "end_to_end_seconds": elapsed,
                            "he_compute_seconds": None,
                            "maximum_absolute_error": absolute,
                            "maximum_relative_error": relative,
                            **metadata,
                        }
                    )
                python_median = statistics.median(python_times)
                summaries.append(
                    {
                        "operation": operation,
                        "backend": "python",
                        "value_count": size,
                        "chunks": chunk_count,
                        "result_scope": result_scope(
                            operation, size, args.sum_request_size
                        ),
                        "repetitions": args.repetitions,
                        "service_seconds": python_median,
                        "he_compute_seconds": None,
                        "end_to_end_seconds": python_median,
                        "values_per_second": size / max(python_median, 1e-12),
                        "maximum_absolute_error": 0.0,
                        "maximum_relative_error": 0.0,
                        "accuracy_passed": True,
                        **metadata,
                    }
                )

                for backend, base_url in (
                    ("cpu", args.cpu_url),
                    ("gpu", args.gpu_url),
                ):
                    service_times: list[float] = []
                    round_trip_times: list[float] = []
                    he_compute_times: list[float | None] = []
                    maximum_absolute = 0.0
                    maximum_relative = 0.0
                    for repetition in range(1, args.repetitions + 1):
                        print(
                            f"{backend.upper()} {operation}: {profile}, "
                            f"{size} values, repetition {repetition}",
                            flush=True,
                        )
                        service, round_trip, he_compute, observed, responses = (
                            run_service_repetition(
                                base_url,
                                operation,
                                values_a,
                                values_b,
                                args.chunk_size,
                                args.sum_request_size,
                                args.timeout,
                            )
                        )
                        absolute, relative = maximum_errors(observed, expected)
                        maximum_absolute = max(maximum_absolute, absolute)
                        maximum_relative = max(maximum_relative, relative)
                        service_times.append(service)
                        round_trip_times.append(round_trip)
                        he_compute_times.append(he_compute)
                        details.append(
                            {
                                "operation": operation,
                                "backend": backend,
                                "value_count": size,
                                "chunks": chunk_count,
                                "repetition": repetition,
                                "service_seconds": service,
                                "end_to_end_seconds": round_trip,
                                "he_compute_seconds": he_compute,
                                "maximum_absolute_error": absolute,
                                "maximum_relative_error": relative,
                                "service_responses": responses,
                                **metadata,
                            }
                        )
                    passed = (
                        maximum_absolute <= args.abs_tolerance
                        or maximum_relative <= args.rel_tolerance
                    )
                    all_passed = all_passed and passed
                    median_round_trip = statistics.median(round_trip_times)
                    summaries.append(
                        {
                            "operation": operation,
                            "backend": backend,
                            "value_count": size,
                            "chunks": chunk_count,
                            "result_scope": result_scope(
                                operation, size, args.sum_request_size
                            ),
                            "repetitions": args.repetitions,
                            "service_seconds": statistics.median(service_times),
                            "he_compute_seconds": median_optional(he_compute_times),
                            "end_to_end_seconds": median_round_trip,
                            "values_per_second": size
                            / max(median_round_trip, 1e-12),
                            "maximum_absolute_error": maximum_absolute,
                            "maximum_relative_error": maximum_relative,
                            "accuracy_passed": passed,
                            **metadata,
                        }
                    )

    print(
        "\noperation backend profile values chunks service_s "
        "end_to_end_s abs_error pass"
    )
    for row in summaries:
        print(
            f"{row['operation']:<9} {row['backend']:<7} "
            f"{row['data_profile']:<20} "
            f"{row['value_count']:>7} {row['chunks']:>6} "
            f"{row['service_seconds']:>9.4f} "
            f"{row['end_to_end_seconds']:>12.4f} "
            f"{row['maximum_absolute_error']:>9.3g} "
            f"{str(row['accuracy_passed']):>5}"
        )

    result = {
        "configuration": {
            "operations": operations,
            "sizes": sorted(set(args.sizes)),
            "data_profiles": profiles,
            "chunk_size": args.chunk_size,
            "sum_request_size": args.sum_request_size,
            "input_bound": [-INPUT_BOUND, INPUT_BOUND],
            "seed": args.seed,
            "repetitions": args.repetitions,
            "abs_tolerance": args.abs_tolerance,
            "rel_tolerance": args.rel_tolerance,
        },
        "summary": summaries,
        "details": details,
    }
    print(MARKER + json.dumps(result, separators=(",", ":")))
    if not all_passed:
        raise SystemExit("CPU or GPU result exceeded the configured accuracy tolerance")
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cpu-url", default="http://he-evaluator:8080")
    parser.add_argument("--gpu-url", default="http://he-evaluator-gpu:8080")
    parser.add_argument("--operations", nargs="+", default=["all"])
    parser.add_argument("--sizes", type=int, nargs="+", default=[4096])
    parser.add_argument(
        "--data-profiles",
        nargs="+",
        default=["positive_decimal_3"],
        help="named real-number profiles, or 'all' for all ten profiles",
    )
    parser.add_argument("--chunk-size", type=int, default=4096)
    parser.add_argument("--sum-request-size", type=int, default=1_000_000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=3600.0)
    parser.add_argument("--abs-tolerance", type=float, default=0.1)
    parser.add_argument("--rel-tolerance", type=float, default=1e-6)
    args = parser.parse_args()
    if not args.sizes or min(args.sizes) < 1 or max(args.sizes) > 10_000_000:
        parser.error("sizes must be between 1 and 10000000")
    if not 1 <= args.chunk_size <= 4096:
        parser.error("--chunk-size must be between 1 and 4096")
    if not 1 <= args.sum_request_size <= 1_000_000:
        parser.error("--sum-request-size must be between 1 and 1000000")
    try:
        expand_profiles(args.data_profiles)
    except ValueError as error:
        parser.error(str(error))
    if args.repetitions < 1:
        parser.error("--repetitions must be positive")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    return args


if __name__ == "__main__":
    run_benchmark(parse_args())
