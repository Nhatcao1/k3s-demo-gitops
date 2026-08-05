#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [gpu-image-tag]" >&2
  exit 2
fi

image_tag=${1:-$HE_GPU_IMAGE_TAG}
case "$image_tag" in
  *[!0-9A-Za-z._-]*|"")
    echo "Image tag contains unsupported characters." >&2
    exit 2
    ;;
esac

if [ "$#" -eq 1 ]; then
  HE_GPU_IMAGE="$HE_IMAGE_REPOSITORY:$image_tag"
fi

template="$repo_dir/k8s/fides-simple-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"
rendered_yaml=$(mktemp)
trap 'rm -f "$rendered_yaml"' EXIT HUP INT TERM

export HE_NAMESPACE HE_GPU_IMAGE

python3 "$renderer" "$template" > "$rendered_yaml"
he_kubectl -n "$HE_NAMESPACE" delete job he-fides-simple \
  --ignore-not-found >/dev/null
he_kubectl create -f "$rendered_yaml"

if ! he_kubectl -n "$HE_NAMESPACE" wait \
  --for=condition=complete job/he-fides-simple --timeout=15m; then
  he_kubectl -n "$HE_NAMESPACE" get pod -l app=he-fides-simple -o wide || true
  he_kubectl -n "$HE_NAMESPACE" describe job/he-fides-simple || true
  he_kubectl -n "$HE_NAMESPACE" logs job/he-fides-simple || true
  exit 1
fi

he_kubectl -n "$HE_NAMESPACE" logs job/he-fides-simple
