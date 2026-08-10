#!/usr/bin/env python3
"""Extract one HE comparison result marker from a Kubernetes Job log."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import sys


CASE_MARKER = "HE_COMPARISON_CASE="
RUN_MARKER = "HE_COMPARISON_RUN="


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <job.log> <output-dir>")
    log_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    marked_cases = [
        line[len(CASE_MARKER) :]
        for line in log_path.read_text(encoding="utf-8").splitlines()
        if line.startswith(CASE_MARKER)
    ]
    if not marked_cases:
        raise SystemExit(
            f"expected at least one {CASE_MARKER} marker in {log_path}"
        )
    cases = [json.loads(marked) for marked in marked_cases]
    summaries = [row for case in cases for row in case.get("summary", [])]
    details = [row for case in cases for row in case.get("details", [])]
    run_markers = [
        line[len(RUN_MARKER) :]
        for line in log_path.read_text(encoding="utf-8").splitlines()
        if line.startswith(RUN_MARKER)
    ]
    run = json.loads(run_markers[-1]) if run_markers else {}
    payload = {
        "configuration": run.get("configuration"),
        "accuracy_passed": run.get("accuracy_passed"),
        "completed_cases": [
            {
                "data_profile": case.get("data_profile"),
                "value_count": case.get("value_count"),
            }
            for case in cases
        ],
        "summary": summaries,
        "details": details,
    }
    if not summaries:
        raise SystemExit("benchmark cases contain no summary rows")
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / "result.json"
    result_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    summary_path = output_dir / "summary.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=list(summaries[0]))
        writer.writeheader()
        writer.writerows(summaries)
    print(f"Result JSON: {result_path}")
    print(f"Summary CSV: {summary_path}")


if __name__ == "__main__":
    main()
