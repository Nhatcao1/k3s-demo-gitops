#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
repo_dir=$(CDPATH= cd -- "$demo_dir/../.." && pwd)
env_file=${DEMO_ENV_FILE:-$demo_dir/demo.env}
. "$env_file"

csv_file=$DEMO_CSV_FILE
case "$csv_file" in
  /*) ;;
  *) csv_file=$demo_dir/$csv_file ;;
esac
test -f "$csv_file" || {
  echo "Create $csv_file from salaries.example.csv first." >&2
  exit 1
}

export DEMO_NAMESPACE DEMO_HE_IMAGE DEMO_POSTGRES_IMAGE DEMO_POSTGRES_STORAGE
renderer=$repo_dir/scripts/render-he-yaml.py
render() { python3 "$renderer" "$demo_dir/k8s/$1"; }

kubectl create namespace "$DEMO_NAMESPACE" --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null

if ! kubectl -n "$DEMO_NAMESPACE" get secret cpu-postgres-demo-db >/dev/null 2>&1; then
  db_password=$(openssl rand -hex 24)
  kubectl -n "$DEMO_NAMESPACE" create secret generic cpu-postgres-demo-db \
    --from-literal=POSTGRES_DB="$DEMO_POSTGRES_DB" \
    --from-literal=POSTGRES_USER="$DEMO_POSTGRES_USER" \
    --from-literal=POSTGRES_PASSWORD="$db_password" \
    --from-literal=PGDATABASE="$DEMO_POSTGRES_DB" \
    --from-literal=PGUSER="$DEMO_POSTGRES_USER" \
    --from-literal=PGPASSWORD="$db_password"
  unset db_password
fi

if ! kubectl -n "$DEMO_NAMESPACE" get secret cpu-postgres-demo-key >/dev/null 2>&1; then
  wrap_key=$(openssl rand -base64 32 | tr -d '\n')
  kubectl -n "$DEMO_NAMESPACE" create secret generic cpu-postgres-demo-key \
    --from-literal=DEMO_KEY_WRAP_KEY="$wrap_key"
  unset wrap_key
fi

kubectl -n "$DEMO_NAMESPACE" create secret generic cpu-postgres-demo-input \
  --from-file=salaries.csv="$csv_file" \
  --from-literal=DEMO_KPI="$DEMO_KPI" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$DEMO_NAMESPACE" create configmap cpu-postgres-demo-config \
  --from-literal=DEMO_SESSION_ID="$DEMO_SESSION_ID" \
  --from-literal=DEMO_SCHEME="$DEMO_SCHEME" \
  --from-literal=DEMO_KPI_SCALE="$DEMO_KPI_SCALE" \
  --from-literal=DEMO_TOLERANCE="$DEMO_TOLERANCE" \
  --from-literal=DEMO_BGV_PLAINTEXT_MODULUS="$DEMO_BGV_PLAINTEXT_MODULUS" \
  --from-literal=DEMO_SALARIES_CSV=/input/salaries.csv \
  --from-literal=PGHOST=cpu-postgres-demo \
  --from-literal=PGPORT=5432 \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

render schema-configmap.yaml | kubectl apply -f -
render postgres.yaml | kubectl apply -f -
kubectl -n "$DEMO_NAMESPACE" rollout status statefulset/cpu-postgres-demo --timeout=10m

run_job() {
  manifest=$1
  job_name=$(render "$manifest" | kubectl create -f - -o jsonpath='{.metadata.name}')
  echo "job/$job_name"
  kubectl -n "$DEMO_NAMESPACE" wait --for=condition=complete "job/$job_name" --timeout=15m || {
    kubectl -n "$DEMO_NAMESPACE" logs "job/$job_name" --all-containers=true || true
    exit 1
  }
  kubectl -n "$DEMO_NAMESPACE" logs "job/$job_name" --all-containers=true
}

run_job schema-job.yaml
run_job initialize-job.yaml
run_job sum-job.yaml
run_job multiply-job.yaml
run_job verify-job.yaml
run_job inspect-job.yaml
