#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"

count=${1:-$DEMO_SALARY_COUNT}
kpi=${2:-}
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

if ! awk -v minimum="$DEMO_KPI_MIN" -v maximum="$DEMO_KPI_MAX" \
  'BEGIN { exit !(minimum <= maximum) }'; then
  echo "DEMO_KPI_MIN must not exceed DEMO_KPI_MAX" >&2
  exit 2
fi

if [ -z "$kpi" ]; then
  kpi=$(awk -v minimum="$DEMO_KPI_MIN" -v maximum="$DEMO_KPI_MAX" \
    -v scale="$DEMO_KPI_SCALE" 'BEGIN {
      srand()
      low = int(minimum * scale + 0.5)
      high = int(maximum * scale + 0.5)
      print int(low + rand() * (high - low + 1)) / scale
    }')
fi
if ! awk -v value="$kpi" -v minimum="$DEMO_KPI_MIN" \
  -v maximum="$DEMO_KPI_MAX" \
  'BEGIN { exit !(value >= minimum && value <= maximum) }'; then
  echo "KPI must be between $DEMO_KPI_MIN and $DEMO_KPI_MAX" >&2
  exit 2
fi

awk -v count="$count" -v minimum="$DEMO_SALARY_MIN" \
  -v maximum="$DEMO_SALARY_MAX" 'BEGIN {
    srand()
    print "salary"
    for (i = 0; i < count; i++)
      print int(minimum + rand() * (maximum - minimum + 1))
  }' > "$output"

input_file=$DEMO_INPUT_FILE
case "$input_file" in
  /*) ;;
  *) input_file=$demo_dir/$input_file ;;
esac
printf 'DEMO_KPI=%s\n' "$kpi" > "$input_file"

echo "$output"
echo "$input_file"
echo "KPI=$kpi"
