#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

: "${HE_EVALUATE_API_PVC:=he-evaluate-api-artifacts}"
: "${HE_EVALUATE_API_STORAGE:=2Gi}"

rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT HUP INT TERM

export HE_NAMESPACE HE_EVALUATE_API_PVC HE_EVALUATE_API_STORAGE
python3 "$repo_dir/scripts/render-he-yaml.py" \
  "$repo_dir/k8s/evaluate-api-pvc.yaml" > "$rendered"
he_kubectl get namespace "$HE_NAMESPACE" >/dev/null 2>&1 || \
  he_kubectl create namespace "$HE_NAMESPACE"
he_kubectl apply -f "$rendered"
he_kubectl -n "$HE_NAMESPACE" get "pvc/$HE_EVALUATE_API_PVC"

echo "Encrypted artifact PVC applied: $HE_NAMESPACE/$HE_EVALUATE_API_PVC"
echo "A WaitForFirstConsumer storage class may keep it Pending until the first test Job."
