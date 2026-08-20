#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [notebook-image-tag]" >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  image_tag=$1
  case "$image_tag" in
    *[!0-9A-Za-z._-]*|"")
      echo "Image tag contains unsupported characters." >&2
      exit 2
      ;;
  esac
  notebook_image="$HE_IMAGE_REPOSITORY:$image_tag"
else
  notebook_image=$HE_NOTEBOOK_IMAGE
fi

case "$notebook_image" in
  ""|*[[:space:]]*)
    echo "HE_NOTEBOOK_IMAGE must be one valid image reference." >&2
    exit 2
    ;;
esac

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render the notebook manifest." >&2
  exit 1
}

notebook_file="$repo_dir/notebooks/he_playground.ipynb"
template="$repo_dir/k8s/he-notebook.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"
rendered_yaml=$(mktemp)
configmap_yaml=$(mktemp)
trap 'rm -f "$rendered_yaml" "$configmap_yaml"' EXIT HUP INT TERM

he_kubectl get namespace "$HE_NAMESPACE" >/dev/null 2>&1 || \
  he_kubectl create namespace "$HE_NAMESPACE"

# Preserve an existing access token. HE_NOTEBOOK_TOKEN is only consulted when
# the Secret does not exist, so rerunning this deployment does not log or rotate
# credentials unexpectedly.
if ! he_kubectl -n "$HE_NAMESPACE" get secret "$HE_NOTEBOOK_SECRET" >/dev/null 2>&1; then
  notebook_token=${HE_NOTEBOOK_TOKEN:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')}
  he_kubectl -n "$HE_NAMESPACE" create secret generic "$HE_NOTEBOOK_SECRET" \
    --from-literal="token=$notebook_token" >/dev/null
  echo "Created notebook access Secret: $HE_NOTEBOOK_SECRET"
fi

he_kubectl -n "$HE_NAMESPACE" create configmap "$HE_NOTEBOOK_CONFIGMAP" \
  --from-file="he_playground.ipynb=$notebook_file" \
  --dry-run=client -o yaml > "$configmap_yaml"
he_kubectl apply -f "$configmap_yaml" >/dev/null

HE_NOTEBOOK_IMAGE=$notebook_image
export HE_NAMESPACE HE_NOTEBOOK_IMAGE HE_NOTEBOOK_DEPLOYMENT
export HE_NOTEBOOK_SERVICE HE_NOTEBOOK_PVC HE_NOTEBOOK_CONFIGMAP
export HE_NOTEBOOK_SECRET HE_NOTEBOOK_PORT HE_NOTEBOOK_STORAGE
export HE_NOTEBOOK_BACKEND HE_NOTEBOOK_GPU_DEVICE HE_NOTEBOOK_WORKSPACE
export HE_NOTEBOOK_REQUEST_CPU HE_NOTEBOOK_REQUEST_MEMORY
export HE_NOTEBOOK_LIMIT_CPU HE_NOTEBOOK_LIMIT_MEMORY
export HE_NOTEBOOK_GPU_COUNT HE_NOTEBOOK_GPU_NODE_NAME
export HE_NOTEBOOK_GPU_TAINT_VALUE

python3 "$renderer" "$template" > "$rendered_yaml"
he_kubectl apply -f "$rendered_yaml"

# A ConfigMap update does not change the Pod template. Restart so the init
# container always writes he_playground.latest.ipynb from the current Git copy.
he_kubectl -n "$HE_NAMESPACE" rollout restart \
  "deployment/$HE_NOTEBOOK_DEPLOYMENT"
if ! he_kubectl -n "$HE_NAMESPACE" rollout status \
  "deployment/$HE_NOTEBOOK_DEPLOYMENT" --timeout=15m; then
  echo "GPU Notebook rollout failed. Current Pod state:" >&2
  he_kubectl -n "$HE_NAMESPACE" get pods \
    -l "app=$HE_NOTEBOOK_DEPLOYMENT" -o wide >&2 || true
  echo "GPU Notebook startup/preflight log:" >&2
  he_kubectl -n "$HE_NAMESPACE" logs \
    "deployment/$HE_NOTEBOOK_DEPLOYMENT" \
    -c jupyterlab --tail=200 >&2 || true
  echo "GPU Notebook Pod events and scheduling detail:" >&2
  he_kubectl -n "$HE_NAMESPACE" describe pods \
    -l "app=$HE_NOTEBOOK_DEPLOYMENT" >&2 || true
  exit 1
fi

echo "GPU Notebook is ready and passed its T4 startup preflight."
echo "It remains private behind a ClusterIP Service."
echo "Next: ./scripts/notebook/open.sh"
