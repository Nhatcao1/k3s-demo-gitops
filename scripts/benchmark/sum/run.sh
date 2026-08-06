#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render the benchmark Job." >&2
  exit 1
}
command -v gzip >/dev/null 2>&1 || {
  echo "gzip is required to package the benchmark code." >&2
  exit 1
}

namespace=$HE_NAMESPACE
client_image=${SUM_BENCH_IMAGE:-$HE_BENCH_CLIENT_IMAGE}
job_timeout=${BENCH_JOB_TIMEOUT_SECONDS:-43200}
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}
job_name="he-sum-benchmark-$run_id"
output_dir=${OUTPUT_DIR:-"$repo_dir/benchmark_runs/sum/$run_id"}
template="$repo_dir/k8s/sum-benchmark-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM
arguments_file="$temporary_dir/arguments.txt"
cpu_archive="$temporary_dir/compare_sum.py.gz"
generator_archive="$temporary_dir/generate_data.py.gz"
rendered_job="$temporary_dir/job.yaml"

: > "$arguments_file"
if [ "$#" -gt 0 ]; then
  printf '%s\n' "$@" > "$arguments_file"
fi
gzip -c "$script_dir/compare_sum.py" > "$cpu_archive"
gzip -c "$script_dir/generate_data.py" > "$generator_archive"

echo "Benchmark namespace: $namespace"
echo "Benchmark client image: $client_image"
he_kubectl -n "$namespace" get "deployment/$HE_CPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$namespace" get "deployment/$HE_GPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$namespace" get "service/$HE_CPU_SERVICE" >/dev/null
he_kubectl -n "$namespace" get "service/$HE_GPU_SERVICE" >/dev/null
he_kubectl -n "$namespace" rollout status \
  "deployment/$HE_CPU_DEPLOYMENT" --timeout=2m
he_kubectl -n "$namespace" rollout status \
  "deployment/$HE_GPU_DEPLOYMENT" --timeout=2m

he_kubectl -n "$namespace" create configmap he-sum-benchmark-code \
  --from-file=compare_sum.py.gz="$cpu_archive" \
  --from-file=generate_data.py.gz="$generator_archive" \
  --from-file=arguments.txt="$arguments_file" \
  --dry-run=client -o yaml |
  he_kubectl apply -f -

SUM_BENCH_JOB_NAME=$job_name
SUM_BENCH_CLIENT_IMAGE=$client_image
SUM_BENCH_CPU_URL="http://${HE_CPU_SERVICE}:${HE_SERVICE_PORT}/v1/demo/sum"
SUM_BENCH_GPU_URL="http://${HE_GPU_SERVICE}:${HE_SERVICE_PORT}/v1/demo/sum"
SUM_BENCH_JOB_TIMEOUT_SECONDS=$job_timeout
export HE_NAMESPACE SUM_BENCH_JOB_NAME SUM_BENCH_CLIENT_IMAGE
export SUM_BENCH_CPU_URL SUM_BENCH_GPU_URL SUM_BENCH_JOB_TIMEOUT_SECONDS

python3 "$renderer" "$template" > "$rendered_job"
he_kubectl -n "$namespace" delete "job/$job_name" \
  --ignore-not-found >/dev/null
he_kubectl create -f "$rendered_job"

case "$job_timeout" in
  *[!0-9]*|""|0)
    echo "BENCH_JOB_TIMEOUT_SECONDS must be a positive integer." >&2
    exit 2
    ;;
esac

wait_for_job() {
  elapsed=0
  while [ "$elapsed" -lt "$job_timeout" ]; do
    conditions=$(he_kubectl -n "$namespace" get "job/$job_name" \
      -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}')
    case "$conditions" in
      *Complete=True*) return 0 ;;
      *Failed=True*) return 1 ;;
    esac
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

mkdir -p "$output_dir"
job_log="$output_dir/job.log"
if ! wait_for_job; then
  he_kubectl -n "$namespace" logs "job/$job_name" \
    --all-containers=true > "$job_log" 2>&1 || true
  sed -n '1,240p' "$job_log" >&2
  python3 "$script_dir/extract_result.py" "$job_log" "$output_dir" || true
  he_kubectl -n "$namespace" describe "job/$job_name" || true
  exit 1
fi

he_kubectl -n "$namespace" logs "job/$job_name" > "$job_log"
sed -n '1,240p' "$job_log"
python3 "$script_dir/extract_result.py" "$job_log" "$output_dir"

echo "Kubernetes Job: $namespace/$job_name"
echo "Results: $output_dir"
