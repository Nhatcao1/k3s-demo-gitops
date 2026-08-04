#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 <cpu|gpu> <primitive|sum> <50000|100000|500000|1000000|10000000|all>" >&2
  exit 2
}

[ "$#" -eq 3 ] || usage
backend=$1
workload=$2
requested_size=$3

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/benchmarks/he/matrix.env"

case "$backend" in
  cpu|gpu) ;;
  *) usage ;;
esac
case "$workload" in
  primitive|sum) ;;
  *) usage ;;
esac

contains_size() {
  for allowed in $BENCHMARK_SIZES; do
    [ "$allowed" = "$1" ] && return 0
  done
  return 1
}

if [ "$requested_size" = "all" ]; then
  sizes=$BENCHMARK_SIZES
elif contains_size "$requested_size"; then
  sizes=$requested_size
else
  usage
fi

if [ "$backend" = "gpu" ]; then
  echo "GPU is pending: the FIDESlib image builds, but its primitive/SUM worker is not implemented yet." >&2
  exit 3
fi

he_repo=${HE_REPO:-"$HOME/Desktop/Viettel/end2end_homecredit_lgbm"}
prepared_dir=${PREPARED_DIR:-"$he_repo/data/prepared/installments_columns"}
source_csv=${SOURCE_CSV:-"$he_repo/data/home_credit/installments_payments.csv"}
python_bin=${PYTHON_BIN:-python3}
repetitions=${REPETITIONS:-$DEFAULT_REPETITIONS}
run_id=${RUN_ID:-"$(date -u +%Y%m%dT%H%M%SZ)"}
destination=${OUTPUT_DIR:-"$he_repo/benchmark_runs/${backend}_${workload}_$run_id"}

cd "$he_repo"
if [ "$workload" = "primitive" ]; then
  "$python_bin" -m code.openfhe_direct.benchmarks.primitives \
    --prepared-dir "$prepared_dir" \
    --value-count $sizes \
    --operation $PRIMITIVE_OPERATIONS \
    --repetitions "$repetitions" \
    --output-dir "$destination"
else
  "$python_bin" -m code.openfhe_direct.benchmarks.payment_diff_sum_mean \
    --operation sum \
    --installments "$source_csv" \
    --value-count $sizes \
    --repetitions "$repetitions" \
    --output-dir "$destination"
fi

echo "Results: $destination"
