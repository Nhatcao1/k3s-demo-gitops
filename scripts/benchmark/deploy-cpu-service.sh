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

image_tag=${1:-$HE_CPU_IMAGE_TAG}
case "$image_tag" in
  *[!0-9A-Za-z._-]*|"")
    echo "Image tag contains unsupported characters." >&2
    exit 2
    ;;
esac

namespace=$HE_NAMESPACE
if [ "$#" -eq 1 ]; then
  image="$HE_IMAGE_REPOSITORY:$image_tag"
else
  image=$HE_CPU_IMAGE
fi
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

HE_CPU_IMAGE=$image
export HE_NAMESPACE HE_CPU_IMAGE HE_CPU_DEPLOYMENT HE_CPU_SERVICE HE_SERVICE_PORT

he_kubectl get namespace "$namespace" >/dev/null 2>&1 || he_kubectl create namespace "$namespace"

python3 "$renderer" "$template" > "$rendered_yaml"
he_kubectl apply -f "$rendered_yaml"

# A moving tag needs a fresh rollout even when the rendered YAML is unchanged.
he_kubectl -n "$namespace" rollout restart "deployment/$deployment"

he_kubectl -n "$namespace" rollout status "deployment/$deployment" \
  --timeout=10m

echo "CPU evaluator: http://$service:$HE_SERVICE_PORT"
