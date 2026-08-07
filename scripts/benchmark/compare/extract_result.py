#!/usr/bin/env python3
"""Extract one HE comparison result marker from a Kubernetes Job log."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import sys


MARKER = "HE_COMPARISON_RESULT="


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <job.log> <output-dir>")
    log_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    marked = [
        line[len(MARKER) :]
        for line in log_path.read_text(encoding="utf-8").splitlines()
        if line.startswith(MARKER)
    ]
    if len(marked) != 1:
        raise SystemExit(
            f"expected one {MARKER} marker in {log_path}, found {len(marked)}"
        )
    payload = json.loads(marked[0])
    summaries = payload.get("summary")
    if not isinstance(summaries, list) or not summaries:
        raise SystemExit("benchmark result contains no summary rows")
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
