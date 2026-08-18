#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT HUP INT TERM
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"
. "$repo_dir/scripts/lib/benchmark-jobs.sh"

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
  "$repo_dir/k8s/he-notebook.yaml" \
  "$repo_dir/k8s/he-postgres.yaml" \
  "$repo_dir/k8s/he-postgres-schema-job.yaml" \
  "$repo_dir/k8s/sdk-smoke-job.yaml" \
  "$repo_dir/fides-examples/k8s/simple-job.yaml" \
  "$repo_dir/fides-examples/k8s/serial-job.yaml" \
  "$repo_dir/k8s/benchmark-job.yaml" \
  "$repo_dir/k8s/he-comparison-data-pvc.yaml" \
  "$repo_dir/k8s/he-comparison-data-job.yaml" \
  "$repo_dir/k8s/he-comparison-job.yaml" \
  "$repo_dir/k8s/he-multiply-range-job.yaml" \
  "$repo_dir/k8s/evaluate-api-pvc.yaml" \
  "$repo_dir/k8s/evaluate-api-test-job.yaml" \
  "$repo_dir/k8s/sum-benchmark-job.yaml"; do
  test -f "$template"
done
test -f "$repo_dir/scripts/render-he-yaml.py"
test -f "$repo_dir/scripts/lib/benchmark-jobs.sh"
test -f "$repo_dir/scripts/sdk/test_sdk.py"
test -f "$repo_dir/notebooks/he_playground.ipynb"
test -f "$repo_dir/postgres/schema/001_he_store.sql"
test -f "$repo_dir/postgres/schema/002_ciphertext_chunks.sql"
test -x "$repo_dir/scripts/notebook/deploy.sh"
test -x "$repo_dir/scripts/notebook/open.sh"
test -x "$repo_dir/scripts/postgres/deploy.sh"
test -x "$repo_dir/scripts/postgres/forward.sh"
test -x "$repo_dir/scripts/sdk/run-smoke.sh"
test -x "$repo_dir/scripts/benchmark/compare/run.sh"
test -x "$repo_dir/scripts/benchmark/compare/prepare-data.sh"
test -f "$repo_dir/scripts/benchmark/compare/compare_operations.py"
test -f "$repo_dir/scripts/benchmark/compare/data_profiles.py"
test -f "$repo_dir/scripts/benchmark/compare/generate_data.py"
test -f "$repo_dir/scripts/benchmark/compare/extract_result.py"
test -x "$repo_dir/scripts/benchmark/multiply-range/run.sh"
test -f "$repo_dir/scripts/benchmark/multiply-range/multiply_range.py"
test -f "$repo_dir/scripts/benchmark/multiply-range/extract_result.py"
test -x "$repo_dir/scripts/benchmark/sum-range/run.sh"
test -x "$repo_dir/scripts/evaluate-api/setup.sh"
test -x "$repo_dir/scripts/evaluate-api/run-operation.sh"
test -x "$repo_dir/scripts/evaluate-api/run-all.sh"
for operation in add subtract multiply square sum mean variance; do
  test -x "$repo_dir/scripts/evaluate-api/$operation.sh"
  test -x "$repo_dir/scripts/evaluate-api/test_$operation.py"
done

export HE_NAMESPACE HE_CPU_IMAGE HE_GPU_IMAGE HE_FIDES_EXAMPLES_IMAGE
export HE_CPU_DEPLOYMENT HE_GPU_DEPLOYMENT HE_CPU_SERVICE HE_GPU_SERVICE
export HE_SERVICE_PORT
export HE_NOTEBOOK_IMAGE HE_NOTEBOOK_DEPLOYMENT HE_NOTEBOOK_SERVICE
export HE_NOTEBOOK_PVC HE_NOTEBOOK_CONFIGMAP HE_NOTEBOOK_SECRET
export HE_NOTEBOOK_PORT HE_NOTEBOOK_STORAGE HE_NOTEBOOK_REQUEST_CPU
export HE_NOTEBOOK_REQUEST_MEMORY HE_NOTEBOOK_LIMIT_CPU
export HE_NOTEBOOK_LIMIT_MEMORY
export HE_POSTGRES_IMAGE HE_POSTGRES_STATEFULSET HE_POSTGRES_SERVICE
export HE_POSTGRES_PVC HE_POSTGRES_SECRET HE_POSTGRES_SCHEMA_CONFIGMAP
export HE_POSTGRES_SCHEMA_JOB_PREFIX HE_POSTGRES_PORT HE_POSTGRES_STORAGE
export HE_POSTGRES_REQUEST_CPU HE_POSTGRES_REQUEST_MEMORY
export HE_POSTGRES_LIMIT_CPU HE_POSTGRES_LIMIT_MEMORY
export HE_CPU_REQUEST_CPU HE_CPU_REQUEST_MEMORY HE_CPU_LIMIT_CPU
export HE_CPU_LIMIT_MEMORY HE_GPU_REQUEST_CPU HE_GPU_REQUEST_MEMORY
export HE_GPU_LIMIT_CPU HE_GPU_LIMIT_MEMORY HE_GPU_COUNT
export HE_BENCH_REQUEST_CPU HE_BENCH_REQUEST_MEMORY HE_BENCH_LIMIT_CPU
export HE_BENCH_LIMIT_MEMORY HE_BENCH_TMP_STORAGE
export HE_SDK_SMOKE_JOB HE_SDK_SMOKE_TIMEOUT_SECONDS HE_SDK_SMOKE_TTL_SECONDS
export HE_SDK_SMOKE_REQUEST_CPU HE_SDK_SMOKE_REQUEST_MEMORY
export HE_SDK_SMOKE_LIMIT_CPU HE_SDK_SMOKE_LIMIT_MEMORY
export HE_SDK_SMOKE_TMP_STORAGE
export HE_SUM_BENCH_REQUEST_CPU HE_SUM_BENCH_REQUEST_MEMORY
export HE_SUM_BENCH_LIMIT_CPU HE_SUM_BENCH_LIMIT_MEMORY
export HE_SUM_BENCH_TMP_STORAGE
export HE_COMPARE_REQUEST_CPU HE_COMPARE_REQUEST_MEMORY HE_COMPARE_LIMIT_CPU
export HE_COMPARE_LIMIT_MEMORY HE_COMPARE_TMP_STORAGE
export HE_COMPARE_DATA_REQUEST_CPU HE_COMPARE_DATA_REQUEST_MEMORY
export HE_COMPARE_DATA_LIMIT_CPU HE_COMPARE_DATA_LIMIT_MEMORY
export HE_COMPARE_DATA_TMP_STORAGE HE_COMPARE_JOB_TTL_SECONDS
export HE_MULTIPLY_RANGE_REQUEST_CPU HE_MULTIPLY_RANGE_REQUEST_MEMORY
export HE_MULTIPLY_RANGE_LIMIT_CPU HE_MULTIPLY_RANGE_LIMIT_MEMORY
export HE_MULTIPLY_RANGE_TMP_STORAGE
export HE_EVALUATE_API_PVC HE_EVALUATE_API_STORAGE
export HE_EVALUATE_API_REQUEST_CPU HE_EVALUATE_API_REQUEST_MEMORY
export HE_EVALUATE_API_LIMIT_CPU HE_EVALUATE_API_LIMIT_MEMORY
export HE_EVALUATE_API_TMP_STORAGE HE_EVALUATE_API_JOB_TTL_SECONDS
export HE_EVALUATE_API_JOB_TIMEOUT_SECONDS
export HE_EVALUATE_API_REQUEST_TIMEOUT_SECONDS HE_EVALUATE_API_TOLERANCE
export HE_NORMAL_DATA_PVC HE_NORMAL_DATA_STORAGE
export HE_STRESS_DATA_PVC HE_STRESS_DATA_STORAGE

he_select_comparison_data_volume --data-profiles stress
test "$HE_COMPARE_DATA_PVC" = "$HE_STRESS_DATA_PVC"
test "$HE_COMPARE_DATA_STORAGE" = "$HE_STRESS_DATA_STORAGE"
test "$HE_COMPARE_DATA_PREPARE_GROUP" = stress
he_select_comparison_data_volume --data-profiles all
test "$HE_COMPARE_DATA_PVC" = "$HE_NORMAL_DATA_PVC"
test "$HE_COMPARE_DATA_STORAGE" = "$HE_NORMAL_DATA_STORAGE"
test "$HE_COMPARE_DATA_PREPARE_GROUP" = all

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

HE_SDK_SMOKE_IMAGE=$HE_CPU_IMAGE
export HE_SDK_SMOKE_IMAGE

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

HE_MULTIPLY_RANGE_JOB_NAME=he-multiply-range-validation
HE_MULTIPLY_RANGE_CLIENT_IMAGE=$HE_BENCH_CLIENT_IMAGE
HE_MULTIPLY_RANGE_CPU_URL="http://${HE_CPU_SERVICE}:${HE_SERVICE_PORT}"
HE_MULTIPLY_RANGE_GPU_URL="http://${HE_GPU_SERVICE}:${HE_SERVICE_PORT}"
HE_MULTIPLY_RANGE_JOB_TIMEOUT_SECONDS=43200
export HE_MULTIPLY_RANGE_JOB_NAME HE_MULTIPLY_RANGE_CLIENT_IMAGE
export HE_MULTIPLY_RANGE_CPU_URL HE_MULTIPLY_RANGE_GPU_URL
export HE_MULTIPLY_RANGE_JOB_TIMEOUT_SECONDS

HE_EVALUATE_API_JOB_NAME=he-evaluate-cpu-add-validation
HE_EVALUATE_API_CLIENT_IMAGE=$HE_BENCH_CLIENT_IMAGE
HE_EVALUATE_API_OPERATION=add
HE_EVALUATE_API_BACKEND=cpu
HE_EVALUATE_API_RUN_ID=validation
HE_EVALUATE_API_URL="http://${HE_CPU_SERVICE}:${HE_SERVICE_PORT}"
export HE_EVALUATE_API_JOB_NAME HE_EVALUATE_API_CLIENT_IMAGE
export HE_EVALUATE_API_OPERATION HE_EVALUATE_API_BACKEND
export HE_EVALUATE_API_RUN_ID HE_EVALUATE_API_URL

python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/cpu-evaluator.yaml" > "$render_dir/cpu.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/gpu-evaluator.yaml" > "$render_dir/gpu.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/he-notebook.yaml" > "$render_dir/notebook.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/he-postgres.yaml" > "$render_dir/postgres.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/he-postgres-schema-job.yaml" > "$render_dir/postgres-schema-job.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/sdk-smoke-job.yaml" > "$render_dir/sdk-smoke.yaml"
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
  "$repo_dir/k8s/he-multiply-range-job.yaml" > "$render_dir/he-multiply-range.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/evaluate-api-pvc.yaml" > "$render_dir/evaluate-api-pvc.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/evaluate-api-test-job.yaml" > "$render_dir/evaluate-api-job.yaml"
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/sum-benchmark-job.yaml" > "$render_dir/sum-benchmark.yaml"

for rendered in \
  "$render_dir/cpu.yaml" \
  "$render_dir/gpu.yaml" \
  "$render_dir/notebook.yaml" \
  "$render_dir/postgres.yaml" \
  "$render_dir/postgres-schema-job.yaml" \
  "$render_dir/sdk-smoke.yaml" \
  "$render_dir/fides-simple.yaml" \
  "$render_dir/fides-serial.yaml" \
  "$render_dir/benchmark.yaml" \
  "$render_dir/he-comparison-data-pvc.yaml" \
  "$render_dir/he-comparison-data-job.yaml" \
  "$render_dir/he-comparison.yaml" \
  "$render_dir/he-multiply-range.yaml" \
  "$render_dir/evaluate-api-pvc.yaml" \
  "$render_dir/evaluate-api-job.yaml" \
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
grep -q "name: $HE_NOTEBOOK_DEPLOYMENT" "$render_dir/notebook.yaml"
grep -q "image: $HE_NOTEBOOK_IMAGE" "$render_dir/notebook.yaml"
grep -q "claimName: $HE_NOTEBOOK_PVC" "$render_dir/notebook.yaml"
grep -q "name: $HE_NOTEBOOK_CONFIGMAP" "$render_dir/notebook.yaml"
grep -q "name: $HE_NOTEBOOK_SECRET" "$render_dir/notebook.yaml"
grep -q 'type: ClusterIP' "$render_dir/notebook.yaml"
grep -q 'automountServiceAccountToken: false' "$render_dir/notebook.yaml"
grep -q "name: $HE_POSTGRES_STATEFULSET" "$render_dir/postgres.yaml"
grep -q "image: $HE_POSTGRES_IMAGE" "$render_dir/postgres.yaml"
grep -q "claimName: $HE_POSTGRES_PVC" "$render_dir/postgres.yaml"
grep -q "name: $HE_POSTGRES_SECRET" "$render_dir/postgres.yaml"
grep -q 'type: ClusterIP' "$render_dir/postgres.yaml"
grep -q "generateName: $HE_POSTGRES_SCHEMA_JOB_PREFIX" "$render_dir/postgres-schema-job.yaml"
grep -q "name: $HE_POSTGRES_SCHEMA_CONFIGMAP" "$render_dir/postgres-schema-job.yaml"
grep -q "value: $HE_POSTGRES_SERVICE" "$render_dir/postgres-schema-job.yaml"
grep -q 'artifact_sets, ciphertext_chunks' "$render_dir/postgres-schema-job.yaml"
grep -q 'CREATE TABLE IF NOT EXISTS he_store.runs' "$repo_dir/postgres/schema/001_he_store.sql"
grep -q 'CREATE TABLE IF NOT EXISTS he_store.artifacts' "$repo_dir/postgres/schema/001_he_store.sql"
grep -q 'CREATE TABLE IF NOT EXISTS he_store.artifact_sets' "$repo_dir/postgres/schema/002_ciphertext_chunks.sql"
grep -q 'CREATE TABLE IF NOT EXISTS he_store.ciphertext_chunks' "$repo_dir/postgres/schema/002_ciphertext_chunks.sql"
grep -q "name: $HE_SDK_SMOKE_JOB" "$render_dir/sdk-smoke.yaml"
grep -q "image: $HE_SDK_SMOKE_IMAGE" "$render_dir/sdk-smoke.yaml"
grep -q '/opt/he-sdk-wheel/he_looming_sdk-.*\.whl' "$render_dir/sdk-smoke.yaml"
grep -q 'sha256sum -c SHA256SUMS' "$render_dir/sdk-smoke.yaml"
grep -q 'python -m he_sdk.smoke' "$render_dir/sdk-smoke.yaml"
grep -q "memory: $HE_SDK_SMOKE_LIMIT_MEMORY" "$render_dir/sdk-smoke.yaml"
grep -q 'name: he-fides-simple' "$render_dir/fides-simple.yaml"
grep -q 'command:' "$render_dir/fides-simple.yaml"
grep -q '/usr/local/bin/fides-simple' "$render_dir/fides-simple.yaml"
grep -q "image: $HE_FIDES_EXAMPLES_IMAGE" "$render_dir/fides-simple.yaml"
grep -q '/usr/local/bin/fides-serial' "$render_dir/fides-serial.yaml"
grep -q "image: $HE_FIDES_EXAMPLES_IMAGE" "$render_dir/fides-serial.yaml"
grep -q "name: $BENCH_JOB_NAME" "$render_dir/benchmark.yaml"
grep -q "cpu: \"$HE_BENCH_LIMIT_CPU\"" "$render_dir/benchmark.yaml"
grep -q "sizeLimit: $HE_BENCH_TMP_STORAGE" "$render_dir/benchmark.yaml"
grep -q "name: $HE_COMPARE_JOB_NAME" "$render_dir/he-comparison.yaml"
if grep -q 'ttlSecondsAfterFinished:' "$render_dir/he-comparison.yaml"; then
  echo "Comparison Job must be retained for log recovery." >&2
  exit 1
fi
grep -q "memory: $HE_COMPARE_LIMIT_MEMORY" "$render_dir/he-comparison.yaml"
grep -q "sizeLimit: $HE_COMPARE_TMP_STORAGE" "$render_dir/he-comparison.yaml"
grep -q "name: $HE_COMPARE_DATA_PVC" "$render_dir/he-comparison-data-pvc.yaml"
grep -q "storage: $HE_COMPARE_DATA_STORAGE" "$render_dir/he-comparison-data-pvc.yaml"
grep -q "name: $HE_COMPARE_DATA_JOB_NAME" "$render_dir/he-comparison-data-job.yaml"
grep -q "ttlSecondsAfterFinished: $HE_COMPARE_JOB_TTL_SECONDS" "$render_dir/he-comparison-data-job.yaml"
grep -q "memory: $HE_COMPARE_DATA_LIMIT_MEMORY" "$render_dir/he-comparison-data-job.yaml"
grep -q "sizeLimit: $HE_COMPARE_DATA_TMP_STORAGE" "$render_dir/he-comparison-data-job.yaml"
grep -q "claimName: $HE_COMPARE_DATA_PVC" "$render_dir/he-comparison-data-job.yaml"
grep -q 'imagePullPolicy: IfNotPresent' "$render_dir/he-comparison-data-job.yaml"
grep -q "image: $HE_COMPARE_CLIENT_IMAGE" "$render_dir/he-comparison.yaml"
grep -q 'imagePullPolicy: IfNotPresent' "$render_dir/he-comparison.yaml"
grep -q "claimName: $HE_COMPARE_DATA_PVC" "$render_dir/he-comparison.yaml"
grep -q "value: $HE_COMPARE_CPU_URL" "$render_dir/he-comparison.yaml"
grep -q "value: $HE_COMPARE_GPU_URL" "$render_dir/he-comparison.yaml"
grep -q "name: $HE_MULTIPLY_RANGE_JOB_NAME" "$render_dir/he-multiply-range.yaml"
grep -q "image: $HE_MULTIPLY_RANGE_CLIENT_IMAGE" "$render_dir/he-multiply-range.yaml"
grep -q "memory: $HE_MULTIPLY_RANGE_LIMIT_MEMORY" "$render_dir/he-multiply-range.yaml"
grep -q "sizeLimit: $HE_MULTIPLY_RANGE_TMP_STORAGE" "$render_dir/he-multiply-range.yaml"
grep -q "name: $HE_EVALUATE_API_PVC" "$render_dir/evaluate-api-pvc.yaml"
grep -q "storage: $HE_EVALUATE_API_STORAGE" "$render_dir/evaluate-api-pvc.yaml"
grep -q "name: $HE_EVALUATE_API_JOB_NAME" "$render_dir/evaluate-api-job.yaml"
grep -q "image: $HE_EVALUATE_API_CLIENT_IMAGE" "$render_dir/evaluate-api-job.yaml"
grep -q "claimName: $HE_EVALUATE_API_PVC" "$render_dir/evaluate-api-job.yaml"
grep -q "memory: $HE_EVALUATE_API_LIMIT_MEMORY" "$render_dir/evaluate-api-job.yaml"
grep -q "app: $HE_CPU_DEPLOYMENT" "$render_dir/evaluate-api-job.yaml"
grep -q "name: $SUM_BENCH_JOB_NAME" "$render_dir/sum-benchmark.yaml"
grep -q "image: $SUM_BENCH_CLIENT_IMAGE" "$render_dir/sum-benchmark.yaml"
grep -q "memory: $HE_SUM_BENCH_LIMIT_MEMORY" "$render_dir/sum-benchmark.yaml"
grep -q "sizeLimit: $HE_SUM_BENCH_TMP_STORAGE" "$render_dir/sum-benchmark.yaml"
grep -q "value: $SUM_BENCH_CPU_URL" "$render_dir/sum-benchmark.yaml"
grep -q "value: $SUM_BENCH_GPU_URL" "$render_dir/sum-benchmark.yaml"
grep -q 'name: he-dev' "$render_dir/argocd.yaml"
grep -q 'name: he-lab' "$render_dir/argocd.yaml"

echo "HE direct YAML templates and saved Argo CD files passed validation."
