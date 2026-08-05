#!/bin/sh
set -eu

# Only the paused Argo overlay uses the private GitLab registry. The current
# direct CPU/GPU manifests pull public Docker Hub images and do not need this.

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

if [ -z "${REGISTRY_USER:-}" ]; then
  printf "GitLab deploy-token username: "
  IFS= read -r REGISTRY_USER
fi

if [ -z "${REGISTRY_TOKEN:-}" ]; then
  printf "GitLab deploy-token secret: "
  stty -echo
  IFS= read -r REGISTRY_TOKEN
  stty echo
  printf "\n"
fi

for namespace in "$HE_NAMESPACE"; do
  he_kubectl create namespace "$namespace" \
    --dry-run=client -o yaml |
    he_kubectl apply -f -

  he_kubectl -n "$namespace" create secret docker-registry gitlab-registry \
    --docker-server=registry.gitlab.com \
    --docker-username="$REGISTRY_USER" \
    --docker-password="$REGISTRY_TOKEN" \
    --dry-run=client -o yaml |
    he_kubectl apply -f -
done

unset REGISTRY_TOKEN
echo "Registry pull secret is ready in $HE_NAMESPACE."
