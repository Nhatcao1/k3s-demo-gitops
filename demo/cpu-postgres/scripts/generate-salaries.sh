#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"

count=${1:-$DEMO_SALARY_COUNT}
DEMO_KPI=${2:-$DEMO_KPI}
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

if ! awk -v value="$DEMO_KPI" 'BEGIN { exit !(value > 0 && value <= 1) }'; then
  echo "KPI must be greater than 0 and at most 1" >&2
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
printf 'DEMO_KPI=%s\n' "$DEMO_KPI" > "$input_file"

echo "$output"
echo "$input_file"
