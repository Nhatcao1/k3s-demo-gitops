#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT HUP INT TERM
. "$repo_dir/config/he-lab.env"

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required." >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required." >&2
  exit 1
}

for template in \
  "$repo_dir/k8s/cpu-evaluator.yaml" \
  "$repo_dir/k8s/gpu-evaluator.yaml" \
  "$repo_dir/k8s/benchmark-job.yaml"; do
  test -f "$template"
done
test -f "$repo_dir/scripts/render-he-yaml.py"

export HE_NAMESPACE HE_CPU_IMAGE HE_GPU_IMAGE
export HE_CPU_DEPLOYMENT HE_GPU_DEPLOYMENT HE_CPU_SERVICE HE_GPU_SERVICE
export HE_SERVICE_PORT

BENCH_JOB_NAME=he-bench-cpu-primitive-50000-validation
BENCH_BACKEND=cpu
BENCH_WORKLOAD=primitive
BENCH_CLIENT_IMAGE=$HE_BENCH_CLIENT_IMAGE
BENCH_SERVICE_URL=$HE_CPU_SERVICE_URL
BENCH_VALUE_COUNT=50000
BENCH_BATCH_SIZE=8192
BENCH_REPETITIONS=1
BENCH_REQUEST_TIMEOUT_SECONDS=300
BENCH_JOB_TIMEOUT_SECONDS=43200
export BENCH_JOB_NAME BENCH_BACKEND BENCH_WORKLOAD BENCH_CLIENT_IMAGE
export BENCH_SERVICE_URL BENCH_VALUE_COUNT BENCH_BATCH_SIZE BENCH_REPETITIONS
export BENCH_REQUEST_TIMEOUT_SECONDS BENCH_JOB_TIMEOUT_SECONDS

python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/cpu-evaluator.yaml" > "$render_dir/cpu.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/gpu-evaluator.yaml" > "$render_dir/gpu.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/benchmark-job.yaml" > "$render_dir/benchmark.yaml"

for rendered in \
  "$render_dir/cpu.yaml" \
  "$render_dir/gpu.yaml" \
  "$render_dir/benchmark.yaml"; do
  if grep -q '\${' "$rendered"; then
    echo "Unrendered placeholder in $rendered" >&2
    exit 1
  fi
  kubectl apply --dry-run=client --validate=false -f "$rendered" >/dev/null
done

kubectl kustomize "$repo_dir/argocd" \
  > "$render_dir/argocd.yaml"

grep -q "name: $HE_CPU_DEPLOYMENT" "$render_dir/cpu.yaml"
grep -q "image: $HE_CPU_IMAGE" "$render_dir/cpu.yaml"
grep -q "name: $HE_GPU_DEPLOYMENT" "$render_dir/gpu.yaml"
grep -q "image: $HE_GPU_IMAGE" "$render_dir/gpu.yaml"
grep -q "name: $BENCH_JOB_NAME" "$render_dir/benchmark.yaml"
grep -q 'name: he-dev' "$render_dir/argocd.yaml"
grep -q 'name: he-lab' "$render_dir/argocd.yaml"

echo "HE direct YAML templates and saved Argo CD files passed validation."
