#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [image-tag]" >&2
  exit 2
fi

image_tag=${1:-latest}
case "$image_tag" in
  *[!0-9A-Za-z._-]*|"")
    echo "Image tag contains unsupported characters." >&2
    exit 2
    ;;
esac

namespace=${HE_NAMESPACE:-he-dev}
image="registry.gitlab.com/nhatcao99uetwork/k3s-demo-app/openfhe-evaluator-cpu:$image_tag"

kubectl get namespace "$namespace" >/dev/null
kubectl -n "$namespace" get secret gitlab-registry >/dev/null

kubectl -n "$namespace" patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"gitlab-registry"}]}'

kubectl -n "$namespace" create deployment he-evaluator-cpu \
  --image="$image" \
  --port=8080 \
  --dry-run=client -o yaml |
  kubectl apply -f -

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

kubectl -n "$namespace" rollout restart deployment/he-evaluator-cpu

kubectl -n "$namespace" rollout status deployment/he-evaluator-cpu \
  --timeout=10m

echo "Evaluator: http://he-evaluator:8080"
