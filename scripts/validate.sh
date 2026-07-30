#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT HUP INT TERM

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required." >&2
  exit 1
}

kubectl kustomize "$repo_dir/apps/he/overlays/dev" \
  > "$render_dir/he-dev.yaml"
kubectl kustomize "$repo_dir/argocd" \
  > "$render_dir/argocd.yaml"

grep -Eq 'k3s-demo-app/openfhe-gateway:[0-9a-f]{8,40}' "$render_dir/he-dev.yaml"
grep -q 'he-dev.k3s.test' "$render_dir/he-dev.yaml"
grep -q 'namespace: he-dev' "$render_dir/he-dev.yaml"
grep -q 'name: he-gateway' "$render_dir/he-dev.yaml"
grep -q 'name: he-dev' "$render_dir/argocd.yaml"
grep -q 'name: he-lab' "$render_dir/argocd.yaml"

echo "HE Kustomize validation passed."
