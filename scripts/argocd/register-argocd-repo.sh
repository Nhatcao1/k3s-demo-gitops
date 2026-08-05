#!/bin/sh
set -eu

# Register the private GitLab repository only when the Argo CD phase resumes.

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

private_key=${1:-"$HOME/.ssh/id_ed25519_argocd_gitops"}

if [ ! -f "$private_key" ]; then
  echo "Private key not found: $private_key" >&2
  exit 1
fi

he_kubectl -n argocd create secret generic repo-k3s-demo-gitops \
  --from-literal=type=git \
  --from-literal=url=git@gitlab.com:nhatcao99uetwork/k3s-demo-gitops.git \
  --from-file=sshPrivateKey="$private_key" \
  --dry-run=client -o yaml |
  he_kubectl apply -f -

he_kubectl -n argocd label secret repo-k3s-demo-gitops \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo "Argo CD repository credential registered."
