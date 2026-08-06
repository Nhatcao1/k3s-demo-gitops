#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

venv="$repo_dir/.venv-he-sum"
if [ ! -x "$venv/bin/python" ]; then
  echo "Benchmark environment is missing. Run:" >&2
  echo "  python3 -m venv .venv-he-sum" >&2
  echo "  source .venv-he-sum/bin/activate" >&2
  echo "  python3 -m pip install -r scripts/benchmark/sum/requirements.txt" >&2
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

case "$HE_BENCH_PORT_FORWARD_TIMEOUT_SECONDS" in
  *[!0-9]*|""|0)
    echo "HE_BENCH_PORT_FORWARD_TIMEOUT_SECONDS must be a positive integer." >&2
    exit 2
    ;;
esac

show_forward_log() {
  label=$1
  log=$2
  echo "$label port-forward log ($log):" >&2
  sed -n '1,120p' "$log" >&2
}

wait_forward() {
  label=$1
  pid=$2
  ready_url=$3
  log=$4
  waited=0

  while [ "$waited" -lt "$HE_BENCH_PORT_FORWARD_TIMEOUT_SECONDS" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$label port-forward exited before the Service became ready." >&2
      show_forward_log "$label" "$log"
      return 1
    fi
    if "$venv/bin/python" -c \
      'import sys; from urllib.request import urlopen; response = urlopen(sys.argv[1], timeout=2); raise SystemExit(0 if response.status == 200 else 1)' \
      "$ready_url" >/dev/null 2>&1; then
      echo "$label Service ready through local port-forward: $ready_url"
      return 0
    fi
    waited=$((waited + 1))
    sleep 1
  done

  echo "$label Service did not become ready through port-forward after ${HE_BENCH_PORT_FORWARD_TIMEOUT_SECONDS}s." >&2
  show_forward_log "$label" "$log"
  return 1
}

echo "Benchmark namespace: $HE_NAMESPACE"
he_kubectl -n "$HE_NAMESPACE" get "deployment/$HE_CPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$HE_NAMESPACE" get "deployment/$HE_GPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$HE_NAMESPACE" rollout status \
  "deployment/$HE_CPU_DEPLOYMENT" --timeout=2m
he_kubectl -n "$HE_NAMESPACE" rollout status \
  "deployment/$HE_GPU_DEPLOYMENT" --timeout=2m

he_kubectl -n "$HE_NAMESPACE" port-forward \
  "service/$HE_CPU_SERVICE" "$HE_CPU_LOCAL_PORT:$HE_SERVICE_PORT" \
  >"$cpu_log" 2>&1 &
cpu_pid=$!
he_kubectl -n "$HE_NAMESPACE" port-forward \
  "service/$HE_GPU_SERVICE" "$HE_GPU_LOCAL_PORT:$HE_SERVICE_PORT" \
  >"$gpu_log" 2>&1 &
gpu_pid=$!

wait_forward "CPU" "$cpu_pid" \
  "http://127.0.0.1:$HE_CPU_LOCAL_PORT/readyz" "$cpu_log"
wait_forward "GPU" "$gpu_pid" \
  "http://127.0.0.1:$HE_GPU_LOCAL_PORT/readyz" "$gpu_log"

if ! "$venv/bin/python" "$script_dir/compare_sum.py" \
    --cpu-url "http://127.0.0.1:$HE_CPU_LOCAL_PORT/v1/demo/sum" \
    --gpu-url "http://127.0.0.1:$HE_GPU_LOCAL_PORT/v1/demo/sum" \
    --data "$data_file" \
    --output-dir "$output_dir" \
    "$@"; then
  echo "SUM benchmark failed. Port-forward diagnostics follow." >&2
  show_forward_log "CPU" "$cpu_log"
  show_forward_log "GPU" "$gpu_log"
  exit 1
fi
