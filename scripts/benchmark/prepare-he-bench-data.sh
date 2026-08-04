#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/benchmarks/he/matrix.env"

data_dir=${DATA_DIR:-"$repo_dir/data"}
source_csv=${SOURCE_CSV:-"$data_dir/home_credit/installments_payments.csv"}
prepared_dir=${PREPARED_DIR:-"$data_dir/prepared/installments_columns"}
python_bin=${PYTHON_BIN:-python3}

test -f "$script_dir/prepare_full_installments_columns.py" || {
  echo "Missing benchmark helper: $script_dir/prepare_full_installments_columns.py" >&2
  exit 1
}
test -f "$source_csv" || {
  echo "Missing installments CSV: $source_csv" >&2
  exit 1
}

"$python_bin" "$script_dir/prepare_full_installments_columns.py" \
  --input-csv "$source_csv" \
  --output-dir "$prepared_dir" \
  --vector-size 8192 \
  --chunk-rows 100000 \
  --max-rows 0 \
  --overwrite

echo "Prepared data for benchmark sizes: $BENCHMARK_SIZES"
