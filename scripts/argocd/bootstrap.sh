#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

he_kubectl get namespace argocd >/dev/null
he_kubectl apply -f "$repo_dir/argocd/root-application.yaml"
he_kubectl get application counter-root -n argocd
