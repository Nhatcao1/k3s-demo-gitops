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

if [ "$#" -eq 1 ]; then
  image_tag=$1
  case "$image_tag" in
    *[!0-9A-Za-z._-]*|"")
      echo "Image tag contains unsupported characters." >&2
      exit 2
      ;;
  esac
  image="$HE_IMAGE_REPOSITORY:$image_tag"
else
  image=$HE_CPU_IMAGE
fi
case "$image" in
  ""|*[[:space:]]*)
    echo "HE_CPU_IMAGE must be one valid image reference." >&2
    exit 2
    ;;
esac

namespace=$HE_NAMESPACE
deployment=$HE_CPU_DEPLOYMENT
service=$HE_CPU_SERVICE
template="$repo_dir/k8s/cpu-evaluator.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"
rendered_yaml=$(mktemp)
trap 'rm -f "$rendered_yaml"' EXIT HUP INT TERM

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render $template." >&2
  exit 1
}

echo "Using CPU image from configuration: $image"

case "$image" in
  *@sha256:*) restart_for_moving_tag=false ;;
  *) restart_for_moving_tag=true ;;
esac

HE_CPU_IMAGE=$image
export HE_NAMESPACE HE_CPU_IMAGE HE_CPU_DEPLOYMENT HE_CPU_SERVICE HE_SERVICE_PORT
export HE_CPU_REQUEST_CPU HE_CPU_REQUEST_MEMORY HE_CPU_LIMIT_CPU HE_CPU_LIMIT_MEMORY

he_kubectl get namespace "$namespace" >/dev/null 2>&1 || he_kubectl create namespace "$namespace"

python3 "$renderer" "$template" > "$rendered_yaml"
he_kubectl apply -f "$rendered_yaml"

if [ "$restart_for_moving_tag" = "true" ]; then
  he_kubectl -n "$namespace" rollout restart "deployment/$deployment"
fi

he_kubectl -n "$namespace" rollout status "deployment/$deployment" \
  --timeout=10m

echo "CPU evaluator: http://$service:$HE_SERVICE_PORT"
