#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

venv="$repo_dir/.venv-he-sum"
if [ ! -x "$venv/bin/python" ]; then
  echo "Run ./scripts/benchmark/sum/setup.sh first." >&2
  exit 1
fi

run_id=$(date -u +%Y%m%dT%H%M%SZ)
output_dir="$repo_dir/benchmark_runs/sum/$run_id"
data_file="$repo_dir/data/sum-benchmark/values.csv"
mkdir -p "$output_dir"

cpu_log="$output_dir/cpu-port-forward.log"
gpu_log="$output_dir/gpu-port-forward.log"
cpu_pid=
gpu_pid=
cleanup() {
  [ -z "$cpu_pid" ] || kill "$cpu_pid" 2>/dev/null || true
  [ -z "$gpu_pid" ] || kill "$gpu_pid" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

he_kubectl -n "$HE_NAMESPACE" get "deployment/$HE_CPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$HE_NAMESPACE" get "deployment/$HE_GPU_DEPLOYMENT" >/dev/null

he_kubectl -n "$HE_NAMESPACE" port-forward \
  "service/$HE_CPU_SERVICE" "$HE_CPU_LOCAL_PORT:$HE_SERVICE_PORT" \
  >"$cpu_log" 2>&1 &
cpu_pid=$!
he_kubectl -n "$HE_NAMESPACE" port-forward \
  "service/$HE_GPU_SERVICE" "$HE_GPU_LOCAL_PORT:$HE_SERVICE_PORT" \
  >"$gpu_log" 2>&1 &
gpu_pid=$!

sleep 1
if ! kill -0 "$cpu_pid" 2>/dev/null; then
  sed -n '1,80p' "$cpu_log" >&2
  exit 1
fi
if ! kill -0 "$gpu_pid" 2>/dev/null; then
  sed -n '1,80p' "$gpu_log" >&2
  exit 1
fi

"$venv/bin/python" "$script_dir/compare_sum.py" \
  --cpu-url "http://127.0.0.1:$HE_CPU_LOCAL_PORT/v1/demo/sum" \
  --gpu-url "http://127.0.0.1:$HE_GPU_LOCAL_PORT/v1/demo/sum" \
  --data "$data_file" \
  --output-dir "$output_dir" \
  "$@"
