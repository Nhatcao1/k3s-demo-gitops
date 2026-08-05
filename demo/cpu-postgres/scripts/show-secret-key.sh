#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"

manifest=$demo_dir/rendered/show-secret-key-job.yaml
test -f "$manifest" || { echo "Run ./scripts/setup.sh first." >&2; exit 1; }
kube() {
  kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" "$@"
}

job_name=$(kube create -f "$manifest" -o name)
kube -n "$DEMO_NAMESPACE" wait --for=condition=complete \
  "$job_name" --timeout=5m
kube -n "$DEMO_NAMESPACE" logs "$job_name"
