#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
namespace=he-dev

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required." >&2
  exit 1
}

kubectl create namespace "$namespace" --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null

for secret_name in cpu-postgres-demo-db cpu-postgres-demo-input; do
  if ! kubectl -n "$namespace" get secret "$secret_name" >/dev/null 2>&1; then
    echo "Missing Secret $secret_name. Create it with the README.md commands." >&2
    exit 1
  fi
done

if ! kubectl -n "$namespace" get configmap cpu-postgres-demo-config \
  >/dev/null 2>&1; then
  kubectl apply -f "$demo_dir/k8s/configmap.yaml"
fi

kubectl apply \
  -f "$demo_dir/k8s/schema-configmap.yaml" \
  -f "$demo_dir/k8s/postgres.yaml"

kubectl -n "$namespace" rollout status statefulset/cpu-postgres-demo \
  --timeout=10m

run_job() {
  manifest=$1
  job_name=$(kubectl create -f "$demo_dir/k8s/$manifest" \
    -o jsonpath='{.metadata.name}')
  echo "Running job/$job_name"
  if ! kubectl -n "$namespace" wait --for=condition=complete \
    "job/$job_name" --timeout=15m; then
    kubectl -n "$namespace" logs "job/$job_name" --all-containers=true || true
    return 1
  fi
  kubectl -n "$namespace" logs "job/$job_name" --all-containers=true
}

run_job schema-job.yaml
run_job initialize-job.yaml
run_job sum-job.yaml
run_job multiply-job.yaml
run_job verify-job.yaml
run_job inspect-job.yaml

echo "CPU/PostgreSQL HE demo completed."
