#!/bin/sh
set -eu

private_key=${1:-"$HOME/.ssh/id_ed25519_argocd_gitops"}

if [ ! -f "$private_key" ]; then
  echo "Private key not found: $private_key" >&2
  exit 1
fi

kubectl -n argocd create secret generic repo-k3s-demo-gitops \
  --from-literal=type=git \
  --from-literal=url=git@gitlab.com:uet-group1950631/k3s-demo-gitops.git \
  --from-file=sshPrivateKey="$private_key" \
  --dry-run=client -o yaml |
  kubectl apply -f -

kubectl -n argocd label secret repo-k3s-demo-gitops \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo "Argo CD repository credential registered."
