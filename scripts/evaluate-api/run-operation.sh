#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"
. "$repo_dir/scripts/lib/benchmark-jobs.sh"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <add|subtract|multiply|square|sum|mean|variance> [cpu|gpu]" >&2
  exit 2
fi
operation=$1
backend=${2:-cpu}
case "$operation" in
  add|subtract|multiply|square|sum|mean|variance) ;;
  *) echo "Unsupported operation: $operation" >&2; exit 2 ;;
esac
case "$backend" in
  cpu|gpu) ;;
  *) echo "Backend must be cpu or gpu." >&2; exit 2 ;;
esac

# Defaults also live here so an older, locally customized he-lab.env does not
# produce missing-template-variable failures after a Git pull.
: "${HE_EVALUATE_API_PVC:=he-evaluate-api-artifacts}"
: "${HE_EVALUATE_API_STORAGE:=2Gi}"
: "${HE_EVALUATE_API_REQUEST_CPU:=1}"
: "${HE_EVALUATE_API_REQUEST_MEMORY:=2Gi}"
: "${HE_EVALUATE_API_LIMIT_CPU:=4}"
: "${HE_EVALUATE_API_LIMIT_MEMORY:=8Gi}"
: "${HE_EVALUATE_API_TMP_STORAGE:=1Gi}"
: "${HE_EVALUATE_API_JOB_TTL_SECONDS:=600}"
: "${HE_EVALUATE_API_JOB_TIMEOUT_SECONDS:=1800}"
: "${HE_EVALUATE_API_REQUEST_TIMEOUT_SECONDS:=600}"
: "${HE_EVALUATE_API_TOLERANCE:=0.001}"

namespace=$HE_NAMESPACE
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}
job_name="he-evaluate-${backend}-${operation}-${run_id}"
template="$repo_dir/k8s/evaluate-api-test-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"
rendered=$(mktemp)
job_created=false
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ "$job_created" = "true" ]; then
    he_delete_benchmark_job "$namespace" "job/$job_name" || true
  fi
  rm -f "$rendered"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

he_kubectl -n "$namespace" get "pvc/$HE_EVALUATE_API_PVC" >/dev/null || {
  echo "PVC missing. Run ./scripts/evaluate-api/setup.sh first." >&2
  exit 1
}
he_kubectl -n "$namespace" rollout status \
  "deployment/$HE_CPU_DEPLOYMENT" --timeout=5m
client_image=$(he_kubectl -n "$namespace" get \
  "deployment/$HE_CPU_DEPLOYMENT" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
he_require_immutable_benchmark_image "$client_image" "Trusted client"

if [ "$backend" = "gpu" ]; then
  target_deployment=$HE_GPU_DEPLOYMENT
  target_service=$HE_GPU_SERVICE
else
  target_deployment=$HE_CPU_DEPLOYMENT
  target_service=$HE_CPU_SERVICE
fi
he_kubectl -n "$namespace" rollout status \
  "deployment/$target_deployment" --timeout=10m

he_kubectl -n "$namespace" create configmap he-evaluate-api-test-code \
  --from-file=evaluate_test_common.py="$script_dir/evaluate_test_common.py" \
  --from-file=test_add.py="$script_dir/test_add.py" \
  --from-file=test_subtract.py="$script_dir/test_subtract.py" \
  --from-file=test_multiply.py="$script_dir/test_multiply.py" \
  --from-file=test_square.py="$script_dir/test_square.py" \
  --from-file=test_sum.py="$script_dir/test_sum.py" \
  --from-file=test_mean.py="$script_dir/test_mean.py" \
  --from-file=test_variance.py="$script_dir/test_variance.py" \
  --dry-run=client -o yaml | he_kubectl apply -f -

HE_EVALUATE_API_JOB_NAME=$job_name
HE_EVALUATE_API_CLIENT_IMAGE=$client_image
HE_EVALUATE_API_OPERATION=$operation
HE_EVALUATE_API_BACKEND=$backend
HE_EVALUATE_API_RUN_ID=$run_id
HE_EVALUATE_API_URL="http://${target_service}:${HE_SERVICE_PORT}"
export HE_NAMESPACE HE_CPU_DEPLOYMENT HE_EVALUATE_API_JOB_NAME
export HE_EVALUATE_API_CLIENT_IMAGE HE_EVALUATE_API_OPERATION
export HE_EVALUATE_API_BACKEND HE_EVALUATE_API_RUN_ID HE_EVALUATE_API_URL
export HE_EVALUATE_API_PVC HE_EVALUATE_API_JOB_TTL_SECONDS
export HE_EVALUATE_API_JOB_TIMEOUT_SECONDS HE_EVALUATE_API_REQUEST_TIMEOUT_SECONDS
export HE_EVALUATE_API_TOLERANCE HE_EVALUATE_API_REQUEST_CPU
export HE_EVALUATE_API_REQUEST_MEMORY HE_EVALUATE_API_LIMIT_CPU
export HE_EVALUATE_API_LIMIT_MEMORY HE_EVALUATE_API_TMP_STORAGE

python3 "$renderer" "$template" > "$rendered"
he_kubectl create -f "$rendered"
job_created=true

wait_for_job() {
  elapsed=0
  while [ "$elapsed" -lt "$HE_EVALUATE_API_JOB_TIMEOUT_SECONDS" ]; do
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

if ! wait_for_job; then
  he_kubectl -n "$namespace" logs "job/$job_name" --all-containers=true || true
  he_kubectl -n "$namespace" describe "job/$job_name" >&2 || true
  exit 1
fi
he_kubectl -n "$namespace" logs "job/$job_name"
he_delete_benchmark_job "$namespace" "job/$job_name"
job_created=false
echo "Encrypted inputs/result kept in PVC: $HE_EVALUATE_API_PVC/$backend/$operation/$run_id"
