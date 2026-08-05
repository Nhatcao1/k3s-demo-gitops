#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

echo "=== Nodes ==="
he_kubectl get nodes -o wide

echo "=== Argo CD Applications ==="
he_kubectl get applications -n argocd

echo "=== HE Development ==="
he_kubectl get all,ingress -n "$HE_NAMESPACE" -o wide
