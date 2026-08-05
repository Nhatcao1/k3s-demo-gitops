#!/bin/sh
set -eu

namespace=he-dev
mode=${1:---jobs}

case "$mode" in
  --jobs)
    kubectl -n "$namespace" delete job \
      -l app.kubernetes.io/part-of=cpu-postgres-demo --ignore-not-found
    ;;
  --all)
    kubectl -n "$namespace" delete job \
      -l app.kubernetes.io/part-of=cpu-postgres-demo --ignore-not-found
    kubectl -n "$namespace" delete statefulset cpu-postgres-demo \
      --ignore-not-found
    kubectl -n "$namespace" delete service cpu-postgres-demo \
      --ignore-not-found
    kubectl -n "$namespace" delete networkpolicy cpu-postgres-demo-db \
      --ignore-not-found
    kubectl -n "$namespace" delete configmap \
      cpu-postgres-demo-config cpu-postgres-demo-schema --ignore-not-found
    kubectl -n "$namespace" delete secret \
      cpu-postgres-demo-db cpu-postgres-demo-input --ignore-not-found
    kubectl -n "$namespace" delete pvc database-cpu-postgres-demo-0 \
      --ignore-not-found
    ;;
  *)
    echo "Usage: $0 [--jobs|--all]" >&2
    exit 2
    ;;
esac
