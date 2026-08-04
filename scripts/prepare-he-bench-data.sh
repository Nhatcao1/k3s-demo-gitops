#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/benchmarks/he/matrix.env"

he_repo=${HE_REPO:-"$HOME/Desktop/Viettel/end2end_homecredit_lgbm"}
source_csv=${SOURCE_CSV:-"$he_repo/data/home_credit/installments_payments.csv"}
prepared_dir=${PREPARED_DIR:-"$he_repo/data/prepared/installments_columns"}
python_bin=${PYTHON_BIN:-python3}

test -f "$he_repo/code/heir/scripts/prepare_full_installments_columns.py" || {
  echo "Wrong HE_REPO: $he_repo" >&2
  exit 1
}
test -f "$source_csv" || {
  echo "Missing installments CSV: $source_csv" >&2
  exit 1
}

cd "$he_repo"
"$python_bin" code/heir/scripts/prepare_full_installments_columns.py \
  --input-csv "$source_csv" \
  --output-dir "$prepared_dir" \
  --vector-size 8192 \
  --chunk-rows 100000 \
  --max-rows 0 \
  --overwrite

echo "Prepared data for benchmark sizes: $BENCHMARK_SIZES"
