#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}

RUN_ID=$run_id \
OUTPUT_DIR=${OUTPUT_DIR:-"$repo_dir/benchmark_runs/sum-range/$run_id"} \
exec "$repo_dir/scripts/benchmark/multiply-range/run.sh" \
  --operation sum "$@"
