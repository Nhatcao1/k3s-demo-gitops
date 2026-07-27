#!/bin/sh
set -eu

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

for namespace in counter-dev counter-prod; do
  kubectl create namespace "$namespace" \
    --dry-run=client -o yaml |
    kubectl apply -f -

  kubectl -n "$namespace" create secret docker-registry gitlab-registry \
    --docker-server=registry.gitlab.com \
    --docker-username="$REGISTRY_USER" \
    --docker-password="$REGISTRY_TOKEN" \
    --dry-run=client -o yaml |
    kubectl apply -f -
done

unset REGISTRY_TOKEN
echo "Registry pull secrets are ready in counter-dev and counter-prod."
