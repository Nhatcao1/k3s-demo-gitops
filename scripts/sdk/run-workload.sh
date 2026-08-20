#!/bin/sh
set -eu

usage() {
  cat >&2 <<'EOF'
Usage:
  run-workload.sh <cpu|gpu> <operation> <run-id> <left> <output> [right]

Examples:
  ./scripts/sdk/run-workload.sh cpu sum 42 input cpu_sum
  ./scripts/sdk/run-workload.sh gpu sum 42 input gpu_sum
  ./scripts/sdk/run-workload.sh gpu add 42 left added right

The run must already contain a secretless SDK workspace in PostgreSQL.
EOF
  exit 2
}

[ "$#" -ge 5 ] && [ "$#" -le 6 ] || usage

backend=$1
operation=$2
run_id=$3
left=$4
output=$5
right=${6:-__none__}

case "$backend" in
  cpu|gpu) ;;
  *) usage ;;
esac
case "$operation" in
  add|subtract|multiply)
    [ "$right" != "__none__" ] || {
      echo "$operation requires the right artifact argument." >&2
      exit 2
    }
    ;;
  square|sum|mean|variance)
    [ "$right" = "__none__" ] || {
      echo "$operation does not accept a right artifact." >&2
      exit 2
    }
    ;;
  *) usage ;;
esac

case "$run_id" in
  ""|0|*[!0-9]*)
    echo "Run id must be a positive integer." >&2
    exit 2
    ;;
esac
for artifact in "$left" "$output"; do
  case "$artifact" in
    ""|[!A-Za-z]*|*[!0-9A-Za-z_.-]*)
      echo "Artifact names must match [A-Za-z][A-Za-z0-9_.-]*." >&2
      exit 2
      ;;
  esac
done
if [ "$right" != "__none__" ]; then
  case "$right" in
    [!A-Za-z]*|*[!0-9A-Za-z_.-]*)
      echo "Artifact names must match [A-Za-z][A-Za-z0-9_.-]*." >&2
      exit 2
      ;;
  esac
fi
[ "$left" != "$output" ] && [ "$right" != "$output" ] || {
  echo "Output must not overwrite an input artifact." >&2
  exit 2
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render the SDK worker Job." >&2
  exit 1
}
command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required to create the SDK worker Job." >&2
  exit 1
}

case "$backend" in
  cpu)
    template="$repo_dir/jobs/sdk-worker-cpu.yaml"
    HE_SDK_WORKER_IMAGE=$HE_SDK_CPU_WORKER_IMAGE
    HE_SDK_WORKER_JOB_PREFIX=he-sdk-cpu-
    ;;
  gpu)
    template="$repo_dir/jobs/sdk-worker-gpu.yaml"
    HE_SDK_WORKER_IMAGE=$HE_SDK_GPU_WORKER_IMAGE
    HE_SDK_WORKER_JOB_PREFIX=he-sdk-gpu-
    ;;
esac

HE_SDK_RUN_ID=$run_id
HE_SDK_OPERATION=$operation
HE_SDK_LEFT=$left
HE_SDK_RIGHT=$right
HE_SDK_OUTPUT=$output
export HE_NAMESPACE HE_SDK_WORKER_IMAGE HE_SDK_WORKER_JOB_PREFIX
export HE_SDK_RUN_ID HE_SDK_OPERATION HE_SDK_LEFT HE_SDK_RIGHT HE_SDK_OUTPUT
export HE_SDK_WORKER_TIMEOUT_SECONDS
export HE_SDK_WORKER_TTL_SECONDS HE_SDK_WORKER_TMP_STORAGE
export HE_SDK_CPU_WORKER_REQUEST_CPU HE_SDK_CPU_WORKER_REQUEST_MEMORY
export HE_SDK_CPU_WORKER_LIMIT_CPU HE_SDK_CPU_WORKER_LIMIT_MEMORY
export HE_SDK_GPU_WORKER_REQUEST_CPU HE_SDK_GPU_WORKER_REQUEST_MEMORY
export HE_SDK_GPU_WORKER_LIMIT_CPU HE_SDK_GPU_WORKER_LIMIT_MEMORY
export HE_GPU_COUNT HE_GPU_NODE_NAME HE_GPU_TAINT_VALUE
export HE_POSTGRES_SERVICE HE_POSTGRES_PORT HE_POSTGRES_SECRET

rendered_job=$(mktemp)
trap 'rm -f "$rendered_job"' EXIT HUP INT TERM
python3 "$repo_dir/scripts/render-he-yaml.py" "$template" > "$rendered_job"

he_kubectl get namespace "$HE_NAMESPACE" >/dev/null 2>&1 || \
  he_kubectl create namespace "$HE_NAMESPACE"
he_kubectl -n "$HE_NAMESPACE" get secret "$HE_POSTGRES_SECRET" >/dev/null
he_kubectl -n "$HE_NAMESPACE" get service "$HE_POSTGRES_SERVICE" >/dev/null

job_name=$(he_kubectl create -f "$rendered_job" \
  -o jsonpath='{.metadata.name}')
echo "Created $job_name using $HE_SDK_WORKER_IMAGE"

if ! he_kubectl -n "$HE_NAMESPACE" wait --for=condition=complete \
  "job/$job_name" --timeout="${HE_SDK_WORKER_TIMEOUT_SECONDS}s"; then
  he_kubectl -n "$HE_NAMESPACE" logs "job/$job_name" \
    --all-containers=true || true
  he_kubectl -n "$HE_NAMESPACE" describe "job/$job_name" || true
  exit 1
fi

he_kubectl -n "$HE_NAMESPACE" logs "job/$job_name" --all-containers=true
echo "Encrypted result published to PostgreSQL run $run_id as $output"
