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

namespace=${HE_NAMESPACE:-he-dev}
client_image=${BENCH_IMAGE:-registry.gitlab.com/nhatcao99uetwork/k3s-demo-app/openfhe-evaluator-cpu:latest}
if [ "$backend" = "cpu" ]; then
  evaluator_deployment=he-evaluator-cpu
  evaluator_service=he-evaluator
  default_service_url=http://he-evaluator:8080/v1/evaluate
else
  evaluator_deployment=he-evaluator-gpu
  evaluator_service=he-evaluator-gpu
  default_service_url=http://he-evaluator-gpu:8080/v1/evaluate
fi
service_url=${HE_SERVICE_URL:-$default_service_url}
repetitions=${REPETITIONS:-$DEFAULT_REPETITIONS}
batch_size=${BATCH_SIZE:-8192}
request_timeout=${REQUEST_TIMEOUT_SECONDS:-300}
job_timeout=${BENCH_JOB_TIMEOUT_SECONDS:-43200}
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}
output_dir=${OUTPUT_DIR:-"$repo_dir/benchmark_runs/${backend}_${workload}_$run_id"}

kubectl -n "$namespace" get deployment "$evaluator_deployment" >/dev/null
kubectl -n "$namespace" get service "$evaluator_service" >/dev/null
kubectl -n "$namespace" create configmap he-service-benchmark-code \
  --from-file=service_benchmark.py="$script_dir/service_benchmark.py" \
  --dry-run=client -o yaml |
  kubectl apply -f -

mkdir -p "$output_dir"

run_one() {
  size=$1
  job_name="he-bench-${backend}-${workload}-${size}-${run_id}"

  kubectl delete job "$job_name" -n "$namespace" --ignore-not-found >/dev/null
  kubectl apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $job_name
  namespace: $namespace
  labels:
    app: he-service-benchmark
    workload: $workload
    backend: $backend
spec:
  backoffLimit: 0
  activeDeadlineSeconds: $job_timeout
  template:
    metadata:
      labels:
        app: he-service-benchmark
        workload: $workload
        backend: $backend
    spec:
      restartPolicy: Never
      imagePullSecrets:
        - name: gitlab-registry
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
        - name: benchmark-client
          image: $client_image
          imagePullPolicy: Always
          command:
            - python
            - /benchmark/service_benchmark.py
          args:
            - --url
            - $service_url
            - --workload
            - $workload
            - --value-count
            - "$size"
            - --batch-size
            - "$batch_size"
            - --repetitions
            - "$repetitions"
            - --timeout
            - "$request_timeout"
          resources:
            requests:
              cpu: "1"
              memory: 2Gi
            limits:
              cpu: "2"
              memory: 4Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
          volumeMounts:
            - name: benchmark-code
              mountPath: /benchmark
              readOnly: true
            - name: temporary-files
              mountPath: /tmp
      volumes:
        - name: benchmark-code
          configMap:
            name: he-service-benchmark-code
        - name: temporary-files
          emptyDir:
            sizeLimit: 2Gi
YAML

  if ! kubectl wait --for=condition=complete "job/$job_name" \
    -n "$namespace" --timeout="${job_timeout}s"; then
    kubectl -n "$namespace" logs "job/$job_name" --all-containers=true || true
    kubectl -n "$namespace" describe "job/$job_name" || true
    return 1
  fi

  kubectl -n "$namespace" logs "job/$job_name" \
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
