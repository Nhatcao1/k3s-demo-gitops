#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT HUP INT TERM

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required." >&2
  exit 1
}

kubectl kustomize "$repo_dir/apps/counter/overlays/dev" \
  > "$render_dir/counter-dev.yaml"
kubectl kustomize "$repo_dir/apps/counter/overlays/prod" \
  > "$render_dir/counter-prod.yaml"
kubectl kustomize "$repo_dir/argocd" \
  > "$render_dir/argocd.yaml"

grep -Eq 'api:[0-9a-f]{8,40}' "$render_dir/counter-dev.yaml"
grep -Eq 'web:[0-9a-f]{8,40}' "$render_dir/counter-dev.yaml"
grep -q 'counter-dev.k3s.test' "$render_dir/counter-dev.yaml"
grep -q 'namespace: counter-dev' "$render_dir/counter-dev.yaml"

grep -Eq 'api:[0-9a-f]{8,40}' "$render_dir/counter-prod.yaml"
grep -Eq 'web:[0-9a-f]{8,40}' "$render_dir/counter-prod.yaml"
grep -q 'counter-prod.k3s.test' "$render_dir/counter-prod.yaml"
grep -q 'namespace: counter-prod' "$render_dir/counter-prod.yaml"

echo "Kustomize validation passed."
