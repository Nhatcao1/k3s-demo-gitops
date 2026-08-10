#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render the comparison Job." >&2
  exit 1
}
command -v gzip >/dev/null 2>&1 || {
  echo "gzip is required to package the comparison code." >&2
  exit 1
}

namespace=$HE_NAMESPACE
client_image_override=${HE_COMPARE_IMAGE:-}
job_timeout=${BENCH_JOB_TIMEOUT_SECONDS:-43200}
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}
job_name="he-operation-comparison-$run_id"
output_dir=${OUTPUT_DIR:-"$repo_dir/benchmark_runs/compare/$run_id"}
template="$repo_dir/k8s/he-comparison-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM
arguments_file="$temporary_dir/arguments.txt"
code_archive="$temporary_dir/compare_operations.py.gz"
profiles_archive="$temporary_dir/data_profiles.py.gz"
rendered_job="$temporary_dir/job.yaml"

: > "$arguments_file"
if [ "$#" -gt 0 ]; then
  printf '%s\n' "$@" > "$arguments_file"
fi
gzip -c "$script_dir/compare_operations.py" > "$code_archive"
gzip -c "$script_dir/data_profiles.py" > "$profiles_archive"

echo "Comparison namespace: $namespace"
he_kubectl -n "$namespace" get "deployment/$HE_CPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$namespace" get "deployment/$HE_GPU_DEPLOYMENT" >/dev/null
he_kubectl -n "$namespace" get "service/$HE_CPU_SERVICE" >/dev/null
he_kubectl -n "$namespace" get "service/$HE_GPU_SERVICE" >/dev/null
he_kubectl -n "$namespace" get "pvc/$HE_COMPARE_DATA_PVC" >/dev/null || {
  echo "Reusable data PVC is missing. Run:" >&2
  echo "  ./scripts/benchmark/compare/prepare-data.sh --count <largest-size> --data-profiles all" >&2
  exit 1
}
he_kubectl -n "$namespace" wait \
  --for=jsonpath='{.status.phase}'=Bound "pvc/$HE_COMPARE_DATA_PVC" \
  --timeout=2m
he_kubectl -n "$namespace" rollout status \
  "deployment/$HE_CPU_DEPLOYMENT" --timeout=2m
he_kubectl -n "$namespace" rollout status \
  "deployment/$HE_GPU_DEPLOYMENT" --timeout=2m

if [ -n "$client_image_override" ]; then
  client_image=$client_image_override
else
  client_image=$(he_kubectl -n "$namespace" get \
    "deployment/$HE_CPU_DEPLOYMENT" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
fi
case "$client_image" in
  ""|*[[:space:]]*)
    echo "Could not determine one valid comparison client image." >&2
    exit 1
    ;;
esac
echo "Comparison client image: $client_image"

he_kubectl -n "$namespace" create configmap he-operation-comparison-code \
  --from-file=compare_operations.py.gz="$code_archive" \
  --from-file=data_profiles.py.gz="$profiles_archive" \
  --from-file=arguments.txt="$arguments_file" \
  --dry-run=client -o yaml |
  he_kubectl apply -f -

HE_COMPARE_JOB_NAME=$job_name
HE_COMPARE_CLIENT_IMAGE=$client_image
HE_COMPARE_CPU_URL="http://${HE_CPU_SERVICE}:${HE_SERVICE_PORT}"
HE_COMPARE_GPU_URL="http://${HE_GPU_SERVICE}:${HE_SERVICE_PORT}"
HE_COMPARE_JOB_TIMEOUT_SECONDS=$job_timeout
export HE_NAMESPACE HE_COMPARE_JOB_NAME HE_COMPARE_CLIENT_IMAGE HE_COMPARE_DATA_PVC
export HE_COMPARE_CPU_URL HE_COMPARE_GPU_URL HE_COMPARE_JOB_TIMEOUT_SECONDS

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
  he_kubectl -n "$namespace" get pods -l "job-name=$job_name" \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,REASON:.status.containerStatuses[0].state.terminated.reason,EXIT:.status.containerStatuses[0].state.terminated.exitCode' \
    >> "$job_log" 2>&1 || true
  he_kubectl -n "$namespace" describe pods -l "job-name=$job_name" \
    >> "$job_log" 2>&1 || true
  sed -n '1,260p' "$job_log" >&2
  python3 "$script_dir/extract_result.py" "$job_log" "$output_dir" || true
  he_kubectl -n "$namespace" describe "job/$job_name" || true
  exit 1
fi

he_kubectl -n "$namespace" logs "job/$job_name" > "$job_log"
sed -n '1,260p' "$job_log"
python3 "$script_dir/extract_result.py" "$job_log" "$output_dir"

echo "Kubernetes Job: $namespace/$job_name"
echo "Results: $output_dir"
