#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

kubectl get namespace argocd >/dev/null
kubectl apply -f "$repo_dir/argocd/root-application.yaml"
kubectl get application counter-root -n argocd
