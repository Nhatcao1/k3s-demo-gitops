#!/usr/bin/env python3
"""Stream reusable deterministic HE benchmark datasets to CSV files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

from data_profiles import DATA_PROFILES, INPUT_BOUND, expand_profiles, values


FORMAT_VERSION = 1


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def generate_profile(
    output_dir: Path,
    profile: str,
    count: int,
    seed: int,
    force: bool,
) -> dict[str, object]:
    output = output_dir / f"{profile}.csv"
    metadata_path = output_dir / f"{profile}.json"
    if not force and output.is_file() and metadata_path.is_file():
        current = json.loads(metadata_path.read_text(encoding="utf-8"))
        if (
            current.get("format_version") == FORMAT_VERSION
            and current.get("profile") == profile
            and current.get("seed") == seed
            and isinstance(current.get("count"), int)
            and int(current["count"]) >= count
            and current.get("sha256") == file_sha256(output)
        ):
            print(f"Reusing {output} ({current['count']} pairs)", flush=True)
            return current

    output_dir.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".csv.tmp")
    actual_minimum = float("inf")
    actual_maximum = float("-inf")
    _, decimal_places = DATA_PROFILES[profile]
    with temporary.open("w", newline="", encoding="utf-8") as target:
        writer = csv.writer(target)
        writer.writerow(("value_a", "value_b"))
        for left, right in zip(
            values(profile, count, seed, "a"),
            values(profile, count, seed, "b"),
        ):
            writer.writerow(
                (
                    f"{left:.{decimal_places}f}",
                    f"{right:.{decimal_places}f}",
                )
            )
            actual_minimum = min(actual_minimum, left, right)
            actual_maximum = max(actual_maximum, left, right)
    temporary.replace(output)

    sign, decimal_places = DATA_PROFILES[profile]
    metadata: dict[str, object] = {
        "format_version": FORMAT_VERSION,
        "profile": profile,
        "count": count,
        "seed": seed,
        "input_sign": sign,
        "decimal_places": decimal_places,
        "input_bound_min": -INPUT_BOUND,
        "input_bound_max": INPUT_BOUND,
        "input_min": actual_minimum,
        "input_max": actual_maximum,
        "sha256": file_sha256(output),
        "source": "deterministic_reusable_csv",
    }
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {output} ({count} pairs)", flush=True)
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--data-profiles", nargs="+", default=["all"])
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    try:
        profiles = expand_profiles(args.data_profiles)
    except ValueError as error:
        parser.error(str(error))
    for profile in profiles:
        generate_profile(args.output_dir, profile, args.count, args.seed, args.force)


if __name__ == "__main__":
    main()
