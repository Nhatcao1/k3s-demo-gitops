#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"
. "$repo_dir/scripts/lib/benchmark-jobs.sh"

# Keep this runner usable when a server retains an older locally customized
# he-lab.env. Explicit values from that file still take precedence.
: "${HE_MULTIPLY_RANGE_REQUEST_CPU:=1}"
: "${HE_MULTIPLY_RANGE_REQUEST_MEMORY:=512Mi}"
: "${HE_MULTIPLY_RANGE_LIMIT_CPU:=2}"
: "${HE_MULTIPLY_RANGE_LIMIT_MEMORY:=2Gi}"
: "${HE_MULTIPLY_RANGE_TMP_STORAGE:=256Mi}"
: "${HE_COMPARE_JOB_TTL_SECONDS:=600}"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render the multiplication-range Job." >&2
  exit 1
}
command -v gzip >/dev/null 2>&1 || {
  echo "gzip is required to package the benchmark code." >&2
  exit 1
}

namespace=$HE_NAMESPACE
job_timeout=${BENCH_JOB_TIMEOUT_SECONDS:-43200}
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}
job_name="he-multiply-range-$run_id"
output_dir=${OUTPUT_DIR:-"$repo_dir/benchmark_runs/multiply-range/$run_id"}
template="$repo_dir/k8s/he-multiply-range-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"

temporary_dir=$(mktemp -d)
job_created=false
cleanup() {
  cleanup_status=$?
  trap - EXIT HUP INT TERM
  if [ "$job_created" = "true" ]; then
    he_delete_benchmark_job "$namespace" "job/$job_name" || true
  fi
  rm -rf "$temporary_dir"
  exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

arguments_file="$temporary_dir/arguments.txt"
code_archive="$temporary_dir/multiply_range.py.gz"
rendered_job="$temporary_dir/job.yaml"
printf '%s\n' "$@" > "$arguments_file"
gzip -c "$script_dir/multiply_range.py" > "$code_archive"

requested_scheme=CKKS
previous_argument=""
for current_argument in "$@"; do
  if [ "$previous_argument" = "--scheme" ]; then
    requested_scheme=$(printf '%s' "$current_argument" | tr '[:lower:]' '[:upper:]')
  fi
  previous_argument=$current_argument
done

he_kubectl -n "$namespace" get "deployment/$HE_CPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$namespace" get "service/$HE_CPU_SERVICE" >/dev/null
he_kubectl -n "$namespace" rollout status \
  "deployment/$HE_CPU_DEPLOYMENT" --timeout=2m

cpu_image=$(he_kubectl -n "$namespace" get "deployment/$HE_CPU_DEPLOYMENT" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
client_image=${HE_MULTIPLY_RANGE_IMAGE:-$cpu_image}
he_require_immutable_benchmark_image "$cpu_image" "CPU evaluator"
he_require_immutable_benchmark_image "$client_image" "Multiply-range client"

echo "CPU evaluator image: $cpu_image"
if [ "$requested_scheme" = "CKKS" ]; then
  he_kubectl -n "$namespace" get "deployment/$HE_GPU_DEPLOYMENT" >/dev/null
  he_kubectl -n "$namespace" get "service/$HE_GPU_SERVICE" >/dev/null
  he_kubectl -n "$namespace" rollout status \
    "deployment/$HE_GPU_DEPLOYMENT" --timeout=2m
  gpu_image=$(he_kubectl -n "$namespace" get "deployment/$HE_GPU_DEPLOYMENT" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
  he_require_immutable_benchmark_image "$gpu_image" "GPU evaluator"
  echo "GPU evaluator image: $gpu_image"
else
  echo "BGV uses CPU OpenFHE only; GPU FIDESlib is CKKS-only."
fi
echo "Multiply-range client image: $client_image"
echo "This Job generates factor chunks in memory; it mounts no benchmark PVC."

he_kubectl -n "$namespace" create configmap he-multiply-range-code \
  --from-file=multiply_range.py.gz="$code_archive" \
  --from-file=arguments.txt="$arguments_file" \
  --dry-run=client -o yaml | he_kubectl apply -f -

HE_MULTIPLY_RANGE_JOB_NAME=$job_name
HE_MULTIPLY_RANGE_CLIENT_IMAGE=$client_image
HE_MULTIPLY_RANGE_CPU_URL="http://${HE_CPU_SERVICE}:${HE_SERVICE_PORT}"
HE_MULTIPLY_RANGE_GPU_URL="http://${HE_GPU_SERVICE}:${HE_SERVICE_PORT}"
HE_MULTIPLY_RANGE_JOB_TIMEOUT_SECONDS=$job_timeout
export HE_NAMESPACE HE_MULTIPLY_RANGE_JOB_NAME HE_MULTIPLY_RANGE_CLIENT_IMAGE
export HE_MULTIPLY_RANGE_CPU_URL HE_MULTIPLY_RANGE_GPU_URL
export HE_MULTIPLY_RANGE_JOB_TIMEOUT_SECONDS HE_COMPARE_JOB_TTL_SECONDS
export HE_MULTIPLY_RANGE_REQUEST_CPU HE_MULTIPLY_RANGE_REQUEST_MEMORY
export HE_MULTIPLY_RANGE_LIMIT_CPU HE_MULTIPLY_RANGE_LIMIT_MEMORY
export HE_MULTIPLY_RANGE_TMP_STORAGE

python3 "$renderer" "$template" > "$rendered_job"
he_kubectl -n "$namespace" delete "job/$job_name" --ignore-not-found >/dev/null
he_kubectl create -f "$rendered_job"
job_created=true

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
  he_kubectl -n "$namespace" get pods -l "job-name=$job_name" \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,REASON:.status.containerStatuses[0].state.terminated.reason,EXIT:.status.containerStatuses[0].state.terminated.exitCode' \
    >> "$job_log" 2>&1 || true
  sed -n '1,260p' "$job_log" >&2
  python3 "$script_dir/extract_result.py" "$job_log" "$output_dir" || true
  exit 1
fi

he_kubectl -n "$namespace" logs "job/$job_name" > "$job_log"
sed -n '1,260p' "$job_log"
python3 "$script_dir/extract_result.py" "$job_log" "$output_dir"
he_delete_benchmark_job "$namespace" "job/$job_name"
job_created=false

echo "Completed Kubernetes Job (cleaned up): $namespace/$job_name"
echo "Results: $output_dir"
