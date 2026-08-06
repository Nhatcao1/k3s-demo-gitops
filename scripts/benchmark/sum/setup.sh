#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
venv="$repo_dir/.venv-he-sum"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required." >&2
  exit 1
}

python3 -m venv "$venv"
"$venv/bin/python" -m pip install --upgrade pip
"$venv/bin/python" -m pip install -r "$script_dir/requirements.txt"

echo "SUM benchmark environment ready: $venv"
echo "Next: ./scripts/benchmark/sum/run.sh --sizes 50000 --repetitions 1"
