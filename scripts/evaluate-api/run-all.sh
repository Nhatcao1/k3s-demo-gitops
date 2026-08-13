#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend=${1:-cpu}
for operation in add subtract multiply square sum mean variance; do
  "$script_dir/run-operation.sh" "$operation" "$backend"
done
