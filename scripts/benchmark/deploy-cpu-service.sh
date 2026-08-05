#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"

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
image="$HE_IMAGE_REPOSITORY:$image_tag"
deployment=$HE_CPU_DEPLOYMENT
service=$HE_CPU_SERVICE

kubectl get namespace "$namespace" >/dev/null 2>&1 || kubectl create namespace "$namespace"

kubectl -n "$namespace" create deployment "$deployment" \
  --image="$image" \
  --port=8080 \
  --dry-run=client -o yaml |
  kubectl apply -f -

# cpu-latest is a moving tag, so every rollout must check Docker Hub instead
# of silently reusing an older K3s/containerd cache entry.
kubectl -n "$namespace" patch deployment "$deployment" \
  --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]'

kubectl -n "$namespace" set resources "deployment/$deployment" \
  --requests=cpu=1,memory=2Gi \
  --limits=cpu=4,memory=8Gi

kubectl -n "$namespace" set env "deployment/$deployment" \
  MAX_ARTIFACT_BYTES=268435456 \
  MAX_REQUEST_BYTES=536870912

kubectl -n "$namespace" create service clusterip "$service" \
  --tcp="$HE_SERVICE_PORT:$HE_SERVICE_PORT" \
  --dry-run=client -o yaml |
  kubectl apply -f -

# The Service has a stable public name, but it must select the differently
# named CPU Deployment pods.
kubectl -n "$namespace" patch service "$service" \
  --type=merge \
  -p "{\"spec\":{\"selector\":{\"app\":\"$deployment\"}}}"

kubectl -n "$namespace" rollout restart "deployment/$deployment"

kubectl -n "$namespace" rollout status "deployment/$deployment" \
  --timeout=10m

echo "CPU evaluator: http://$service:$HE_SERVICE_PORT"
