#!/usr/bin/env python3
"""Compare Pandas SUM with deployed CPU OpenFHE and GPU FIDESlib services."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import statistics
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import pandas as pd

from generate_data import generate


TIMING_FIELDS = (
    "context_keygen_seconds",
    "encrypt_seconds",
    "sum_seconds",
    "combine_seconds",
    "decrypt_seconds",
    "total_seconds",
)


def wait_ready(endpoint: str, seconds: float = 90.0) -> None:
    ready_url = endpoint.rsplit("/v1/", 1)[0] + "/readyz"
    deadline = time.monotonic() + seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            with urlopen(ready_url, timeout=3) as response:
                if response.status == 200:
                    return
        except (HTTPError, URLError, TimeoutError) as error:
            last_error = error
        time.sleep(1)
    raise RuntimeError(f"service did not become ready at {ready_url}: {last_error}")


def call_sum(
    endpoint: str, values: list[float], timeout: float
) -> tuple[dict[str, Any], float]:
    # End-to-end timing intentionally includes JSON encoding and HTTP transfer.
    started = time.perf_counter()
    body = json.dumps({"values": values}, separators=(",", ":")).encode("utf-8")
    request = Request(
        endpoint,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{endpoint} returned HTTP {error.code}: {detail}") from error
    roundtrip = time.perf_counter() - started
    if not isinstance(result, dict) or not isinstance(result.get("values"), list):
        raise RuntimeError(f"{endpoint} returned an invalid response")
    return result, roundtrip


def errors(result: float, reference: float) -> tuple[float, float]:
    absolute = abs(result - reference)
    relative = absolute / abs(reference) if reference else absolute
    return absolute, relative


def median_timing(responses: list[dict[str, Any]], name: str) -> float:
    values = [
        float(response["timings"][name])
        for response in responses
        if isinstance(response.get("timings"), dict)
        and name in response["timings"]
    ]
    return statistics.median(values) if values else float("nan")


def median_he_compute(responses: list[dict[str, Any]]) -> float:
    """Return encrypted SUM plus encrypted partial-sum combination time."""
    values = []
    for response in responses:
        timings = response.get("timings")
        if not isinstance(timings, dict):
            continue
        values.append(
            float(timings.get("sum_seconds", 0.0))
            + float(timings.get("combine_seconds", 0.0))
        )
    return statistics.median(values) if values else float("nan")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cpu-url", default="http://127.0.0.1:18080/v1/demo/sum")
    parser.add_argument("--gpu-url", default="http://127.0.0.1:18081/v1/demo/sum")
    parser.add_argument(
        "--sizes",
        type=int,
        nargs="+",
        default=[50_000, 100_000, 500_000, 1_000_000],
    )
    parser.add_argument("--min-value", type=float, default=0.0)
    parser.add_argument("--max-value", type=float, default=100.0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=3600.0)
    parser.add_argument("--abs-tolerance", type=float, default=0.1)
    parser.add_argument("--rel-tolerance", type=float, default=1e-6)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--regenerate", action="store_true")
    args = parser.parse_args()

    sizes = sorted(set(args.sizes))
    if not sizes or sizes[0] < 1 or sizes[-1] > 1_000_000:
        raise SystemExit("sizes must be between 1 and 1000000")
    if args.repetitions < 1:
        raise SystemExit("repetitions must be positive")

    generate(
        args.data,
        sizes[-1],
        args.min_value,
        args.max_value,
        args.seed,
        args.regenerate,
    )
    frame = pd.read_csv(args.data)
    if list(frame.columns) != ["value"] or len(frame) < sizes[-1]:
        raise SystemExit("data CSV must contain one value column and enough rows")

    wait_ready(args.cpu_url)
    wait_ready(args.gpu_url)
    warmup_values = frame["value"].iloc[: min(8192, sizes[-1])].tolist()
    print("Warm-up: CPU then GPU (excluded from results)")
    call_sum(args.cpu_url, warmup_values, args.timeout)
    call_sum(args.gpu_url, warmup_values, args.timeout)

    summaries: list[dict[str, Any]] = []
    details: list[dict[str, Any]] = []
    passed = True
    for size in sizes:
        values = frame["value"].iloc[:size]
        value_list = values.tolist()
        reference = math.fsum(value_list)

        pandas_times: list[float] = []
        pandas_results: list[float] = []
        for repetition in range(1, args.repetitions + 1):
            started = time.perf_counter()
            pandas_result = float(values.sum())
            pandas_times.append(time.perf_counter() - started)
            pandas_results.append(pandas_result)
            details.append(
                {
                    "backend": "pandas",
                    "value_count": size,
                    "repetition": repetition,
                    "result": pandas_result,
                    "end_to_end_seconds": pandas_times[-1],
                }
            )

        for backend, endpoint in (("cpu", args.cpu_url), ("gpu", args.gpu_url)):
            responses: list[dict[str, Any]] = []
            roundtrips: list[float] = []
            for repetition in range(1, args.repetitions + 1):
                print(f"{backend.upper()} SUM: {size} values, repetition {repetition}")
                response, roundtrip = call_sum(endpoint, value_list, args.timeout)
                responses.append(response)
                roundtrips.append(roundtrip)
                details.append(
                    {
                        "backend": backend,
                        "value_count": size,
                        "repetition": repetition,
                        "result": float(response["values"][0]),
                        "end_to_end_seconds": roundtrip,
                        "service": response,
                    }
                )

            result = float(responses[-1]["values"][0])
            absolute, relative = errors(result, reference)
            backend_passed = (
                absolute <= args.abs_tolerance or relative <= args.rel_tolerance
            )
            passed = passed and backend_passed
            median_roundtrip = statistics.median(roundtrips)
            compute_seconds = median_he_compute(responses)
            row: dict[str, Any] = {
                "backend": backend,
                "value_count": size,
                "result": result,
                "reference_fsum": reference,
                "abs_error": absolute,
                "rel_error": relative,
                "accuracy_passed": backend_passed,
                "compute_seconds": compute_seconds,
                "compute_values_per_second": size / compute_seconds,
                "end_to_end_seconds": median_roundtrip,
                "values_per_second": size / median_roundtrip,
            }
            for name in TIMING_FIELDS:
                row[name] = median_timing(responses, name)
            summaries.append(row)

        pandas_result = pandas_results[-1]
        absolute, relative = errors(pandas_result, reference)
        pandas_median = statistics.median(pandas_times)
        summaries.append(
            {
                "backend": "pandas",
                "value_count": size,
                "result": pandas_result,
                "reference_fsum": reference,
                "abs_error": absolute,
                "rel_error": relative,
                "accuracy_passed": True,
                "compute_seconds": pandas_median,
                "compute_values_per_second": size / pandas_median,
                "end_to_end_seconds": pandas_median,
                "values_per_second": size / pandas_median,
                **{name: float("nan") for name in TIMING_FIELDS},
            }
        )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    summary_path = args.output_dir / "summary.csv"
    fields = [
        "backend",
        "value_count",
        "result",
        "reference_fsum",
        "abs_error",
        "rel_error",
        "accuracy_passed",
        "compute_seconds",
        "compute_values_per_second",
        "end_to_end_seconds",
        "values_per_second",
        *TIMING_FIELDS,
    ]
    with summary_path.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        writer.writerows(summaries)
    details_path = args.output_dir / "details.json"
    details_path.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")

    print("\nbackend values   compute_s end_to_end_s    abs_error   pass")
    for row in sorted(
        summaries, key=lambda item: (item["value_count"], item["backend"])
    ):
        print(
            f"{row['backend']:<7} {row['value_count']:>7} "
            f"{row['compute_seconds']:>11.4f} "
            f"{row['end_to_end_seconds']:>12.4f} {row['abs_error']:>12.6g} "
            f"{str(row['accuracy_passed']):>6}"
        )
    print(f"\nSummary: {summary_path}")
    print(f"Details: {details_path}")
    print(
        "SUM_BENCHMARK_RESULT="
        + json.dumps(
            {"summary": summaries, "details": details},
            separators=(",", ":"),
        )
    )
    if not passed:
        raise SystemExit("CPU or GPU result exceeded the configured accuracy tolerance")


if __name__ == "__main__":
    main()
