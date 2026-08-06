#!/usr/bin/env python3
"""Generate one deterministic CSV for the Pandas/CPU/GPU SUM comparison."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd


def generate(
    output: Path,
    count: int,
    minimum: float,
    maximum: float,
    seed: int,
    force: bool = False,
) -> Path:
    if count < 1:
        raise ValueError("count must be positive")
    if not minimum < maximum:
        raise ValueError("min-value must be less than max-value")
    metadata_path = output.with_suffix(".json")
    wanted = {
        "count": count,
        "min_value": minimum,
        "max_value": maximum,
        "seed": seed,
    }
    if not force and output.is_file() and metadata_path.is_file():
        current = json.loads(metadata_path.read_text(encoding="utf-8"))
        if current == wanted:
            print(f"Reusing {output}")
            return output

    output.parent.mkdir(parents=True, exist_ok=True)
    values = np.random.default_rng(seed).uniform(minimum, maximum, count)
    pd.DataFrame({"value": values}).to_csv(output, index=False)
    metadata_path.write_text(json.dumps(wanted, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {count} values in {output}")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--count", type=int, default=1_000_000)
    parser.add_argument("--min-value", type=float, default=0.0)
    parser.add_argument("--max-value", type=float, default=100.0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    generate(
        args.output, args.count, args.min_value, args.max_value, args.seed, args.force
    )


if __name__ == "__main__":
    main()
