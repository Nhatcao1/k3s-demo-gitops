#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
repo_dir=$(CDPATH= cd -- "$demo_dir/../.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"

input_file=$DEMO_INPUT_FILE
case "$input_file" in
  /*) ;;
  *) input_file=$demo_dir/$input_file ;;
esac
test -f "$input_file" || {
  echo "Run ./scripts/generate-salaries.sh first." >&2
  exit 1
}
. "$input_file"

csv_file=$DEMO_CSV_FILE
case "$csv_file" in
  /*) ;;
  *) csv_file=$demo_dir/$csv_file ;;
esac
test -f "$csv_file" || {
  echo "Run ./scripts/generate-salaries.sh first." >&2
  exit 1
}

export DEMO_NAMESPACE DEMO_HE_IMAGE DEMO_POSTGRES_IMAGE DEMO_POSTGRES_STORAGE
renderer=$repo_dir/scripts/render-he-yaml.py
rendered_dir=$demo_dir/rendered
mkdir -p "$rendered_dir"
for template in "$demo_dir"/k8s/*.yaml; do
  python3 "$renderer" "$template" > "$rendered_dir/$(basename "$template")"
done

case "$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" in
  true|false) ;;
  *) echo "DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY must be true or false" >&2; exit 2 ;;
esac
kube() {
  kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" "$@"
}

kube create namespace "$DEMO_NAMESPACE" --dry-run=client -o yaml |
  kube apply -f - >/dev/null

if ! kube -n "$DEMO_NAMESPACE" get secret cpu-postgres-demo-db >/dev/null 2>&1; then
  db_password=$(openssl rand -hex 24)
  kube -n "$DEMO_NAMESPACE" create secret generic cpu-postgres-demo-db \
    --from-literal=POSTGRES_DB="$DEMO_POSTGRES_DB" \
    --from-literal=POSTGRES_USER="$DEMO_POSTGRES_USER" \
    --from-literal=POSTGRES_PASSWORD="$db_password" \
    --from-literal=PGDATABASE="$DEMO_POSTGRES_DB" \
    --from-literal=PGUSER="$DEMO_POSTGRES_USER" \
    --from-literal=PGPASSWORD="$db_password"
  unset db_password
fi

if ! kube -n "$DEMO_NAMESPACE" get secret cpu-postgres-demo-key >/dev/null 2>&1; then
  wrap_key=$(openssl rand -base64 32 | tr -d '\n')
  kube -n "$DEMO_NAMESPACE" create secret generic cpu-postgres-demo-key \
    --from-literal=DEMO_KEY_WRAP_KEY="$wrap_key"
  unset wrap_key
fi

kube -n "$DEMO_NAMESPACE" create secret generic cpu-postgres-demo-input \
  --from-file=salaries.csv="$csv_file" \
  --from-literal=DEMO_KPI="$DEMO_KPI" \
  --dry-run=client -o yaml | kube apply -f - >/dev/null

kube -n "$DEMO_NAMESPACE" create configmap cpu-postgres-demo-config \
  --from-literal=DEMO_SESSION_ID="$DEMO_SESSION_ID" \
  --from-literal=DEMO_SCHEME="$DEMO_SCHEME" \
  --from-literal=DEMO_KPI_SCALE="$DEMO_KPI_SCALE" \
  --from-literal=DEMO_TOLERANCE="$DEMO_TOLERANCE" \
  --from-literal=DEMO_BGV_PLAINTEXT_MODULUS="$DEMO_BGV_PLAINTEXT_MODULUS" \
  --from-literal=DEMO_SALARIES_CSV=/input/salaries.csv \
  --from-literal=PGHOST=cpu-postgres-demo \
  --from-literal=PGPORT=5432 \
  --dry-run=client -o yaml | kube apply -f - >/dev/null

kube apply -f "$rendered_dir/schema-configmap.yaml"
kube apply -f "$rendered_dir/postgres.yaml"
kube -n "$DEMO_NAMESPACE" rollout status statefulset/cpu-postgres-demo --timeout=10m

schema_job=$(kube create -f "$rendered_dir/schema-job.yaml" -o name)
kube -n "$DEMO_NAMESPACE" wait --for=condition=complete "$schema_job" --timeout=5m
kube -n "$DEMO_NAMESPACE" logs "$schema_job"

echo "Setup complete. Continue with the README job commands."
