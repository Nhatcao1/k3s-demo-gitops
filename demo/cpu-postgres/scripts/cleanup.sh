#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"

kubectl -n "$DEMO_NAMESPACE" delete job \
  -l app.kubernetes.io/part-of=cpu-postgres-demo --ignore-not-found

if [ "${1:-}" = "--all" ]; then
  kubectl -n "$DEMO_NAMESPACE" delete statefulset cpu-postgres-demo \
    --ignore-not-found
  kubectl -n "$DEMO_NAMESPACE" delete service cpu-postgres-demo \
    --ignore-not-found
  kubectl -n "$DEMO_NAMESPACE" delete networkpolicy cpu-postgres-demo-db \
    --ignore-not-found
  kubectl -n "$DEMO_NAMESPACE" delete configmap \
    cpu-postgres-demo-config cpu-postgres-demo-schema --ignore-not-found
  kubectl -n "$DEMO_NAMESPACE" delete secret \
    cpu-postgres-demo-db cpu-postgres-demo-input cpu-postgres-demo-key \
    --ignore-not-found
  kubectl -n "$DEMO_NAMESPACE" delete pvc database-cpu-postgres-demo-0 \
    --ignore-not-found
fi
