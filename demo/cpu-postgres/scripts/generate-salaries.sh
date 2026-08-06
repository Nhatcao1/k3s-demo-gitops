#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"

count=${1:-$DEMO_SALARY_COUNT}
output=$DEMO_CSV_FILE
case "$output" in
  /*) ;;
  *) output=$demo_dir/$output ;;
esac

case "$count" in
  *[!0-9]*|"") echo "count must be an integer" >&2; exit 2 ;;
esac
if [ "$count" -lt 1 ] || [ "$count" -gt 8192 ]; then
  echo "count must be between 1 and 8192" >&2
  exit 2
fi

if ! awk -v values="$DEMO_KPI_VALUES" 'BEGIN {
  count = split(values, choices, ",")
  if (count < 1) exit 1
  for (i = 1; i <= count; i++)
    if (choices[i] !~ /^(0\.8|0\.9|1\.0|1\.1|1\.2)$/) exit 1
}'; then
  echo "DEMO_KPI_VALUES must contain only 0.8,0.9,1.0,1.1,1.2" >&2
  exit 2
fi

awk -v count="$count" -v minimum="$DEMO_SALARY_MIN" \
  -v maximum="$DEMO_SALARY_MAX" -v kpi_values="$DEMO_KPI_VALUES" 'BEGIN {
    srand()
    kpi_count = split(kpi_values, kpis, ",")
    print "salary,kpi"
    for (i = 0; i < count; i++)
      print int(minimum + rand() * (maximum - minimum + 1)) "," \
        kpis[int(rand() * kpi_count) + 1]
  }' > "$output"

echo "$output"
