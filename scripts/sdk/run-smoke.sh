#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 <cpu-commit-sha-tag>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
image_tag=$1
case "$image_tag" in
  cpu-*) ;;
  *)
    echo "Use the immutable CPU tag printed by GitLab CI: cpu-<short-sha>." >&2
    exit 2
    ;;
esac
image_sha=${image_tag#cpu-}
case "$image_sha" in
  ""|*[!0-9a-f]*)
    echo "Use the immutable CPU tag printed by GitLab CI: cpu-<short-sha>." >&2
    exit 2
    ;;
esac
if [ "${#image_sha}" -lt 8 ] || [ "${#image_sha}" -gt 40 ]; then
  echo "The CPU image SHA must contain 8 to 40 hexadecimal characters." >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"
. "$repo_dir/scripts/lib/benchmark-jobs.sh"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render the SDK smoke Job." >&2
  exit 1
}
command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required to run the SDK smoke Job." >&2
  exit 1
}

image="$HE_IMAGE_REPOSITORY:$image_tag"
he_require_immutable_benchmark_image "$image" "SDK smoke test"

namespace=$HE_NAMESPACE
job_name=$HE_SDK_SMOKE_JOB
template="$repo_dir/k8s/sdk-smoke-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"
rendered_job=$(mktemp)
job_logs=$(mktemp)
trap 'rm -f "$rendered_job" "$job_logs"' EXIT HUP INT TERM

HE_SDK_SMOKE_IMAGE=$image
export HE_NAMESPACE HE_SDK_SMOKE_JOB HE_SDK_SMOKE_IMAGE
export HE_SDK_SMOKE_TIMEOUT_SECONDS HE_SDK_SMOKE_TTL_SECONDS
export HE_SDK_SMOKE_REQUEST_CPU HE_SDK_SMOKE_REQUEST_MEMORY
export HE_SDK_SMOKE_LIMIT_CPU HE_SDK_SMOKE_LIMIT_MEMORY
export HE_SDK_SMOKE_TMP_STORAGE

he_kubectl get namespace "$namespace" >/dev/null 2>&1 || \
  he_kubectl create namespace "$namespace"

python3 "$renderer" "$template" > "$rendered_job"
he_kubectl -n "$namespace" delete "job/$job_name" \
  --ignore-not-found --wait=true >/dev/null
he_kubectl create -f "$rendered_job"

if ! he_kubectl -n "$namespace" wait --for=condition=complete \
  "job/$job_name" --timeout="${HE_SDK_SMOKE_TIMEOUT_SECONDS}s"; then
  he_kubectl -n "$namespace" logs "job/$job_name" \
    --all-containers=true || true
  he_kubectl -n "$namespace" describe "job/$job_name" || true
  exit 1
fi

he_kubectl -n "$namespace" logs "job/$job_name" \
  --all-containers=true > "$job_logs"
cat "$job_logs"

grep -q '^SDK_SMOKE_RESULT=.*"status": "PASS"' "$job_logs" || {
  echo "SDK smoke Job completed without a PASS result." >&2
  exit 1
}

echo "PASS: installed and tested the wheel from $image"
