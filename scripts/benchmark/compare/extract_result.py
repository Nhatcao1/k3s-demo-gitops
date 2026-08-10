#!/usr/bin/env python3
"""Extract one HE comparison result marker from a Kubernetes Job log."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import sys


CASE_MARKER = "HE_COMPARISON_CASE="
RUN_MARKER = "HE_COMPARISON_RUN="
ATTEMPT_MARKER = "HE_COMPARISON_ATTEMPT="
FAILURE_MARKER = "HE_COMPARISON_FAILURE="


def marked_payloads(lines: list[str], marker: str) -> list[dict[str, object]]:
    return [
        json.loads(line[len(marker) :])
        for line in lines
        if line.startswith(marker)
    ]


def termination_hint(log_text: str) -> str:
    for hint in (
        "OOMKilled",
        "DeadlineExceeded",
        "Evicted",
        "Connection refused",
        "TimeoutError",
    ):
        if hint in log_text:
            return hint
    return "interrupted_or_process_exit"


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <job.log> <output-dir>")
    log_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    log_text = log_path.read_text(encoding="utf-8")
    lines = log_text.splitlines()
    cases = marked_payloads(lines, CASE_MARKER)
    attempts = marked_payloads(lines, ATTEMPT_MARKER)
    failures = marked_payloads(lines, FAILURE_MARKER)
    summaries = [row for case in cases for row in case.get("summary", [])]
    details = [row for case in cases for row in case.get("details", [])]
    run_markers = marked_payloads(lines, RUN_MARKER)
    run = run_markers[-1] if run_markers else {}
    completed = {
        (case.get("data_profile"), case.get("value_count")) for case in cases
    }
    if attempts:
        last_attempt = attempts[-1]
        last_case = (
            last_attempt.get("data_profile"),
            last_attempt.get("value_count"),
        )
        explicitly_recorded = any(
            all(
                failure.get(name) == last_attempt.get(name)
                for name in (
                    "data_profile",
                    "value_count",
                    "operation",
                    "backend",
                    "repetition",
                )
            )
            for failure in failures
        )
        if last_case not in completed and not explicitly_recorded:
            failures.append(
                {
                    **last_attempt,
                    "failure_type": "hard_limit_or_interruption",
                    "error_type": termination_hint(log_text),
                    "error_message": (
                        "benchmark process ended before this attempted case "
                        "emitted a result"
                    ),
                }
            )
    payload = {
        "configuration": run.get("configuration"),
        "run_completed": bool(run_markers),
        "accuracy_passed": False if failures else run.get("accuracy_passed"),
        "completed_cases": [
            {
                "data_profile": case.get("data_profile"),
                "value_count": case.get("value_count"),
            }
            for case in cases
        ],
        "summary": summaries,
        "details": details,
        "failures": failures,
    }
    if not summaries and not failures:
        raise SystemExit("benchmark log contains no result or failure markers")
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / "result.json"
    result_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    summary_path = None
    if summaries:
        summary_path = output_dir / "summary.csv"
        with summary_path.open("w", newline="", encoding="utf-8") as output:
            writer = csv.DictWriter(output, fieldnames=list(summaries[0]))
            writer.writeheader()
            writer.writerows(summaries)
    failure_path = None
    if failures:
        failure_path = output_dir / "failures.csv"
        failure_fields = [
            "data_profile",
            "value_count",
            "operation",
            "backend",
            "repetition",
            "failure_type",
            "error_type",
            "error_message",
        ]
        with failure_path.open("w", newline="", encoding="utf-8") as output:
            writer = csv.DictWriter(
                output, fieldnames=failure_fields, extrasaction="ignore"
            )
            writer.writeheader()
            writer.writerows(failures)
    print(f"Result JSON: {result_path}")
    if summary_path is not None:
        print(f"Summary CSV: {summary_path}")
    if failure_path is not None:
        print(f"Failures CSV: {failure_path}")


if __name__ == "__main__":
    main()
