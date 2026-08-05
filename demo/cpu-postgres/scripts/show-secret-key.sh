#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
repo_dir=$(CDPATH= cd -- "$demo_dir/../.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"
export DEMO_NAMESPACE DEMO_HE_IMAGE

job_name=$(python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$demo_dir/k8s/show-secret-key-job.yaml" |
  kubectl create -f - -o jsonpath='{.metadata.name}')
kubectl -n "$DEMO_NAMESPACE" wait --for=condition=complete \
  "job/$job_name" --timeout=5m
kubectl -n "$DEMO_NAMESPACE" logs "job/$job_name"
