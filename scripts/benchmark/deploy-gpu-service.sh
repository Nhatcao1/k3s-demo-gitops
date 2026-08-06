#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [image-tag]" >&2
  exit 2
fi

image_tag=${1:-$HE_GPU_IMAGE_TAG}
case "$image_tag" in
  *[!0-9A-Za-z._-]*|"")
    echo "Image tag contains unsupported characters." >&2
    exit 2
    ;;
esac

namespace=$HE_NAMESPACE
deployment=$HE_GPU_DEPLOYMENT
service=$HE_GPU_SERVICE
template="$repo_dir/k8s/gpu-evaluator.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"
resolver="$repo_dir/scripts/resolve-dockerhub-image.py"
rendered_yaml=$(mktemp)
resolver_error=$(mktemp)
trap 'rm -f "$rendered_yaml" "$resolver_error"' EXIT HUP INT TERM

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render $template." >&2
  exit 1
}

case "$HE_DOCKERHUB_RESOLVE_MODE" in
  auto|required|disabled) ;;
  *)
    echo "HE_DOCKERHUB_RESOLVE_MODE must be auto, required, or disabled." >&2
    exit 2
    ;;
esac

if [ -n "$HE_GPU_IMAGE_OVERRIDE" ]; then
  image=$HE_GPU_IMAGE_OVERRIDE
  echo "Using explicit GPU image: $image"
elif [ "$HE_DOCKERHUB_RESOLVE_MODE" = "disabled" ]; then
  image="$HE_IMAGE_REPOSITORY:$image_tag"
  echo "Docker Hub resolution disabled; using $image"
elif image=$(python3 "$resolver" "$HE_IMAGE_REPOSITORY" "$image_tag" 2>"$resolver_error"); then
  echo "Resolved $HE_IMAGE_REPOSITORY:$image_tag to $image"
elif [ "$HE_DOCKERHUB_RESOLVE_MODE" = "required" ]; then
  sed -n '1,3p' "$resolver_error" >&2
  exit 1
else
  image="$HE_IMAGE_REPOSITORY:$image_tag"
  echo "Warning: Docker Hub is unreachable; using $image directly." >&2
  echo "The cluster registry mirror may return a cached tag." >&2
fi

HE_GPU_IMAGE=$image
export HE_NAMESPACE HE_GPU_IMAGE HE_GPU_DEPLOYMENT HE_GPU_SERVICE HE_SERVICE_PORT

he_kubectl get namespace "$namespace" >/dev/null 2>&1 || he_kubectl create namespace "$namespace"

python3 "$renderer" "$template" > "$rendered_yaml"

# This lab has one allocatable GPU. Remove the existing Deployment completely
# so no old Ready Pod can keep serving and no old Pod can hold the T4 while the
# replacement waits. The Service is preserved and reconnects to the new Pod.
he_kubectl -n "$namespace" delete "deployment/$deployment" \
  --ignore-not-found --wait=true
he_kubectl apply -f "$rendered_yaml"

if ! he_kubectl -n "$namespace" rollout status "deployment/$deployment" \
  --timeout=15m; then
  echo "GPU rollout failed; pod status and startup logs follow:" >&2
  he_kubectl -n "$namespace" get pods -l "app=$deployment" -o wide || true
  he_kubectl -n "$namespace" logs -l "app=$deployment" \
    --all-containers=true --prefix=true --tail=200 || true
  exit 1
fi

he_kubectl -n "$namespace" logs -l "app=$deployment" \
  --all-containers=true --prefix=true --tail=20 || true

echo "GPU evaluator: http://$service:$HE_SERVICE_PORT"
