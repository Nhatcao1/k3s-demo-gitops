#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT HUP INT TERM
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

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
  "$repo_dir/fides-examples/k8s/simple-job.yaml" \
  "$repo_dir/fides-examples/k8s/serial-job.yaml" \
  "$repo_dir/k8s/benchmark-job.yaml" \
  "$repo_dir/k8s/he-comparison-data-pvc.yaml" \
  "$repo_dir/k8s/he-comparison-data-job.yaml" \
  "$repo_dir/k8s/he-comparison-job.yaml" \
  "$repo_dir/k8s/sum-benchmark-job.yaml"; do
  test -f "$template"
done
test -f "$repo_dir/scripts/render-he-yaml.py"
test -f "$repo_dir/scripts/lib/benchmark-jobs.sh"
test -x "$repo_dir/scripts/benchmark/compare/run.sh"
test -x "$repo_dir/scripts/benchmark/compare/prepare-data.sh"
test -f "$repo_dir/scripts/benchmark/compare/compare_operations.py"
test -f "$repo_dir/scripts/benchmark/compare/data_profiles.py"
test -f "$repo_dir/scripts/benchmark/compare/generate_data.py"
test -f "$repo_dir/scripts/benchmark/compare/extract_result.py"

export HE_NAMESPACE HE_CPU_IMAGE HE_GPU_IMAGE HE_FIDES_EXAMPLES_IMAGE
export HE_CPU_DEPLOYMENT HE_GPU_DEPLOYMENT HE_CPU_SERVICE HE_GPU_SERVICE
export HE_SERVICE_PORT
export HE_CPU_REQUEST_CPU HE_CPU_REQUEST_MEMORY HE_CPU_LIMIT_CPU
export HE_CPU_LIMIT_MEMORY HE_GPU_REQUEST_CPU HE_GPU_REQUEST_MEMORY
export HE_GPU_LIMIT_CPU HE_GPU_LIMIT_MEMORY HE_GPU_COUNT

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

SUM_BENCH_JOB_NAME=he-sum-benchmark-validation
SUM_BENCH_CLIENT_IMAGE=$HE_BENCH_CLIENT_IMAGE
SUM_BENCH_CPU_URL="http://${HE_CPU_SERVICE}:${HE_SERVICE_PORT}/v1/demo/sum"
SUM_BENCH_GPU_URL="http://${HE_GPU_SERVICE}:${HE_SERVICE_PORT}/v1/demo/sum"
SUM_BENCH_JOB_TIMEOUT_SECONDS=43200
export SUM_BENCH_JOB_NAME SUM_BENCH_CLIENT_IMAGE SUM_BENCH_CPU_URL
export SUM_BENCH_GPU_URL SUM_BENCH_JOB_TIMEOUT_SECONDS

HE_COMPARE_JOB_NAME=he-operation-comparison-validation
HE_COMPARE_CLIENT_IMAGE=$HE_BENCH_CLIENT_IMAGE
HE_COMPARE_CPU_URL="http://${HE_CPU_SERVICE}:${HE_SERVICE_PORT}"
HE_COMPARE_GPU_URL="http://${HE_GPU_SERVICE}:${HE_SERVICE_PORT}"
HE_COMPARE_JOB_TIMEOUT_SECONDS=43200
HE_COMPARE_DATA_JOB_NAME=he-comparison-data-validation
HE_COMPARE_DATA_JOB_TIMEOUT_SECONDS=43200
HE_COMPARE_DATA_IMAGE=$HE_BENCH_CLIENT_IMAGE
export HE_COMPARE_JOB_NAME HE_COMPARE_CLIENT_IMAGE HE_COMPARE_CPU_URL
export HE_COMPARE_GPU_URL HE_COMPARE_JOB_TIMEOUT_SECONDS HE_COMPARE_DATA_PVC
export HE_COMPARE_DATA_STORAGE HE_COMPARE_DATA_JOB_NAME
export HE_COMPARE_DATA_JOB_TIMEOUT_SECONDS HE_COMPARE_DATA_IMAGE

python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/cpu-evaluator.yaml" > "$render_dir/cpu.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/gpu-evaluator.yaml" > "$render_dir/gpu.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/fides-examples/k8s/simple-job.yaml" > "$render_dir/fides-simple.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/fides-examples/k8s/serial-job.yaml" > "$render_dir/fides-serial.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/benchmark-job.yaml" > "$render_dir/benchmark.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/he-comparison-data-pvc.yaml" > "$render_dir/he-comparison-data-pvc.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/he-comparison-data-job.yaml" > "$render_dir/he-comparison-data-job.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/he-comparison-job.yaml" > "$render_dir/he-comparison.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/sum-benchmark-job.yaml" > "$render_dir/sum-benchmark.yaml"

for rendered in \
  "$render_dir/cpu.yaml" \
  "$render_dir/gpu.yaml" \
  "$render_dir/fides-simple.yaml" \
  "$render_dir/fides-serial.yaml" \
  "$render_dir/benchmark.yaml" \
  "$render_dir/he-comparison-data-pvc.yaml" \
  "$render_dir/he-comparison-data-job.yaml" \
  "$render_dir/he-comparison.yaml" \
  "$render_dir/sum-benchmark.yaml"; do
  if grep -q '\${' "$rendered"; then
    echo "Unrendered placeholder in $rendered" >&2
    exit 1
  fi
  he_kubectl apply --dry-run=client --validate=false -f "$rendered" >/dev/null
done

he_kubectl kustomize "$repo_dir/argocd" \
  > "$render_dir/argocd.yaml"

grep -q "name: $HE_CPU_DEPLOYMENT" "$render_dir/cpu.yaml"
grep -q "image: $HE_CPU_IMAGE" "$render_dir/cpu.yaml"
grep -q "cpu: \"$HE_CPU_REQUEST_CPU\"" "$render_dir/cpu.yaml"
grep -q "memory: $HE_CPU_LIMIT_MEMORY" "$render_dir/cpu.yaml"
grep -q "name: $HE_GPU_DEPLOYMENT" "$render_dir/gpu.yaml"
grep -q "image: $HE_GPU_IMAGE" "$render_dir/gpu.yaml"
grep -q "cpu: \"$HE_GPU_LIMIT_CPU\"" "$render_dir/gpu.yaml"
grep -q "memory: $HE_GPU_LIMIT_MEMORY" "$render_dir/gpu.yaml"
grep -q "nvidia.com/gpu: \"$HE_GPU_COUNT\"" "$render_dir/gpu.yaml"
grep -q 'nodeSelector:' "$render_dir/gpu.yaml"
grep -q 'runtimeClassName: nvidia' "$render_dir/gpu.yaml"
grep -q 'kubernetes.io/hostname: hht-k8s-staging-22' "$render_dir/gpu.yaml"
grep -q 'value: T4' "$render_dir/gpu.yaml"
grep -q 'name: he-fides-simple' "$render_dir/fides-simple.yaml"
grep -q 'command:' "$render_dir/fides-simple.yaml"
grep -q '/usr/local/bin/fides-simple' "$render_dir/fides-simple.yaml"
grep -q "image: $HE_FIDES_EXAMPLES_IMAGE" "$render_dir/fides-simple.yaml"
grep -q '/usr/local/bin/fides-serial' "$render_dir/fides-serial.yaml"
grep -q "image: $HE_FIDES_EXAMPLES_IMAGE" "$render_dir/fides-serial.yaml"
grep -q "name: $BENCH_JOB_NAME" "$render_dir/benchmark.yaml"
grep -q "name: $HE_COMPARE_JOB_NAME" "$render_dir/he-comparison.yaml"
grep -q 'ttlSecondsAfterFinished: 600' "$render_dir/he-comparison.yaml"
grep -q "name: $HE_COMPARE_DATA_PVC" "$render_dir/he-comparison-data-pvc.yaml"
grep -q "storage: $HE_COMPARE_DATA_STORAGE" "$render_dir/he-comparison-data-pvc.yaml"
grep -q "name: $HE_COMPARE_DATA_JOB_NAME" "$render_dir/he-comparison-data-job.yaml"
grep -q 'ttlSecondsAfterFinished: 600' "$render_dir/he-comparison-data-job.yaml"
grep -q "claimName: $HE_COMPARE_DATA_PVC" "$render_dir/he-comparison-data-job.yaml"
grep -q "image: $HE_COMPARE_CLIENT_IMAGE" "$render_dir/he-comparison.yaml"
grep -q "claimName: $HE_COMPARE_DATA_PVC" "$render_dir/he-comparison.yaml"
grep -q "value: $HE_COMPARE_CPU_URL" "$render_dir/he-comparison.yaml"
grep -q "value: $HE_COMPARE_GPU_URL" "$render_dir/he-comparison.yaml"
grep -q "name: $SUM_BENCH_JOB_NAME" "$render_dir/sum-benchmark.yaml"
grep -q "image: $SUM_BENCH_CLIENT_IMAGE" "$render_dir/sum-benchmark.yaml"
grep -q "value: $SUM_BENCH_CPU_URL" "$render_dir/sum-benchmark.yaml"
grep -q "value: $SUM_BENCH_GPU_URL" "$render_dir/sum-benchmark.yaml"
grep -q 'name: he-dev' "$render_dir/argocd.yaml"
grep -q 'name: he-lab' "$render_dir/argocd.yaml"

echo "HE direct YAML templates and saved Argo CD files passed validation."
