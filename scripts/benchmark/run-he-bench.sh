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

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"
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

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required." >&2
  exit 1
}

namespace=$HE_NAMESPACE
client_image=${BENCH_IMAGE:-$HE_BENCH_CLIENT_IMAGE}
if [ "$backend" = "cpu" ]; then
  evaluator_deployment=$HE_CPU_DEPLOYMENT
  evaluator_service=$HE_CPU_SERVICE
  default_service_url=$HE_CPU_SERVICE_URL
else
  evaluator_deployment=$HE_GPU_DEPLOYMENT
  evaluator_service=$HE_GPU_SERVICE
  default_service_url=$HE_GPU_SERVICE_URL
fi
service_url=${HE_SERVICE_URL:-$default_service_url}
repetitions=${REPETITIONS:-$DEFAULT_REPETITIONS}
batch_size=${BATCH_SIZE:-8192}
request_timeout=${REQUEST_TIMEOUT_SECONDS:-300}
job_timeout=${BENCH_JOB_TIMEOUT_SECONDS:-43200}
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}
output_dir=${OUTPUT_DIR:-"$repo_dir/benchmark_runs/${backend}_${workload}_$run_id"}
template="$repo_dir/k8s/benchmark-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render $template." >&2
  exit 1
}
command -v gzip >/dev/null 2>&1 || {
  echo "gzip is required to package the benchmark client." >&2
  exit 1
}

he_kubectl -n "$namespace" get deployment "$evaluator_deployment" >/dev/null
he_kubectl -n "$namespace" get service "$evaluator_service" >/dev/null

# Compress the client before sending it through the Kubernetes API. This keeps
# the ConfigMap request small for lab clusters exposed through strict proxies.
benchmark_archive=$(mktemp)
trap 'rm -f "$benchmark_archive"' EXIT HUP INT TERM
gzip -c "$script_dir/service_benchmark.py" > "$benchmark_archive"
he_kubectl -n "$namespace" create configmap he-service-benchmark-code \
  --from-file=service_benchmark.py.gz="$benchmark_archive" \
  --dry-run=client -o yaml |
  he_kubectl apply -f -

mkdir -p "$output_dir"

run_one() {
  size=$1
  job_name="he-bench-${backend}-${workload}-${size}-${run_id}"

  he_kubectl delete job "$job_name" -n "$namespace" --ignore-not-found >/dev/null
  BENCH_JOB_NAME=$job_name
  BENCH_BACKEND=$backend
  BENCH_WORKLOAD=$workload
  BENCH_CLIENT_IMAGE=$client_image
  BENCH_SERVICE_URL=$service_url
  BENCH_VALUE_COUNT=$size
  BENCH_BATCH_SIZE=$batch_size
  BENCH_REPETITIONS=$repetitions
  BENCH_REQUEST_TIMEOUT_SECONDS=$request_timeout
  BENCH_JOB_TIMEOUT_SECONDS=$job_timeout
  export HE_NAMESPACE BENCH_JOB_NAME BENCH_BACKEND BENCH_WORKLOAD
  export BENCH_CLIENT_IMAGE BENCH_SERVICE_URL BENCH_VALUE_COUNT
  export BENCH_BATCH_SIZE BENCH_REPETITIONS BENCH_REQUEST_TIMEOUT_SECONDS
  export BENCH_JOB_TIMEOUT_SECONDS

  rendered_job=$(mktemp)
  if ! python3 "$renderer" "$template" > "$rendered_job"; then
    rm -f "$rendered_job"
    return 1
  fi
  if ! he_kubectl create -f "$rendered_job"; then
    rm -f "$rendered_job"
    return 1
  fi
  rm -f "$rendered_job"

  if ! he_kubectl wait --for=condition=complete "job/$job_name" \
    -n "$namespace" --timeout="${job_timeout}s"; then
    he_kubectl -n "$namespace" logs "job/$job_name" --all-containers=true || true
    he_kubectl -n "$namespace" describe "job/$job_name" || true
    return 1
  fi

  he_kubectl -n "$namespace" logs "job/$job_name" \
    > "$output_dir/${size}.log"
  sed -n 's/^BENCHMARK_RESULT=//p' "$output_dir/${size}.log" \
    > "$output_dir/${size}.json"
  test -s "$output_dir/${size}.json" || {
    echo "Benchmark completed without a result marker; inspect $output_dir/${size}.log" >&2
    return 1
  }
  echo "PASS: $workload $size -> $output_dir/${size}.json"
}

for size in $sizes; do
  run_one "$size"
done

echo "Results: $output_dir"
