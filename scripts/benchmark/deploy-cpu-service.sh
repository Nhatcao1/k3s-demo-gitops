#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [image-tag]" >&2
  exit 2
fi

image_tag=${1:-cpu-latest}
case "$image_tag" in
  *[!0-9A-Za-z._-]*|"")
    echo "Image tag contains unsupported characters." >&2
    exit 2
    ;;
esac

namespace=${HE_NAMESPACE:-he-dev}
image="docker.io/dockerboi99/he_k8s:$image_tag"

kubectl get namespace "$namespace" >/dev/null 2>&1 || kubectl create namespace "$namespace"

kubectl -n "$namespace" create deployment he-evaluator-cpu \
  --image="$image" \
  --port=8080 \
  --dry-run=client -o yaml |
  kubectl apply -f -

# cpu-latest is a moving tag, so every rollout must check Docker Hub instead
# of silently reusing an older K3s/containerd cache entry.
kubectl -n "$namespace" patch deployment he-evaluator-cpu \
  --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]'

kubectl -n "$namespace" set resources deployment/he-evaluator-cpu \
  --requests=cpu=1,memory=2Gi \
  --limits=cpu=4,memory=8Gi

kubectl -n "$namespace" set env deployment/he-evaluator-cpu \
  MAX_ARTIFACT_BYTES=268435456 \
  MAX_REQUEST_BYTES=536870912

kubectl -n "$namespace" create service clusterip he-evaluator \
  --tcp=8080:8080 \
  --dry-run=client -o yaml |
  kubectl apply -f -

# The Service has a stable public name, but it must select the differently
# named CPU Deployment pods.
kubectl -n "$namespace" patch service he-evaluator \
  --type=merge \
  -p '{"spec":{"selector":{"app":"he-evaluator-cpu"}}}'

kubectl -n "$namespace" rollout restart deployment/he-evaluator-cpu

kubectl -n "$namespace" rollout status deployment/he-evaluator-cpu \
  --timeout=10m

echo "Evaluator: http://he-evaluator:8080"
