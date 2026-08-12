#!/usr/bin/env python3
"""Extract multiplication-range checkpoints and failures from a Job log."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import sys


CASE_MARKER = "HE_MULTIPLY_RANGE_CASE="
ATTEMPT_MARKER = "HE_MULTIPLY_RANGE_ATTEMPT="
FAILURE_MARKER = "HE_MULTIPLY_RANGE_FAILURE="
RUN_MARKER = "HE_MULTIPLY_RANGE_RUN="


def payloads(lines: list[str], marker: str) -> list[dict[str, object]]:
    return [
        json.loads(line[len(marker) :])
        for line in lines
        if line.startswith(marker)
    ]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <job.log> <output-dir>")
    log_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    lines = log_path.read_text(encoding="utf-8").splitlines()
    cases = payloads(lines, CASE_MARKER)
    attempts = payloads(lines, ATTEMPT_MARKER)
    failures = payloads(lines, FAILURE_MARKER)
    runs = payloads(lines, RUN_MARKER)
    if attempts and not runs and not failures:
        failures.append(
            {
                **attempts[-1],
                "failure_type": "hard_limit_or_interruption",
                "error_type": "interrupted_or_process_exit",
                "error_message": "Job ended before the attempted chunk completed",
            }
        )
    if not cases and not failures:
        raise SystemExit("multiplication-range log has no result markers")

    output_dir.mkdir(parents=True, exist_ok=True)
    result = {
        "configuration": runs[-1] if runs else None,
        "run_completed": bool(runs),
        "accuracy_passed": bool(runs) and not failures,
        "checkpoints": cases,
        "failures": failures,
    }
    result_path = output_dir / "result.json"
    result_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if cases:
        with (output_dir / "summary.csv").open(
            "w", newline="", encoding="utf-8"
        ) as output:
            writer = csv.DictWriter(output, fieldnames=list(cases[0]))
            writer.writeheader()
            writer.writerows(cases)
    if failures:
        fields = list(dict.fromkeys(name for row in failures for name in row))
        with (output_dir / "failures.csv").open(
            "w", newline="", encoding="utf-8"
        ) as output:
            writer = csv.DictWriter(output, fieldnames=fields)
            writer.writeheader()
            writer.writerows(failures)
    print(f"Result JSON: {result_path}")


if __name__ == "__main__":
    main()
