#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"

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
image="$HE_IMAGE_REPOSITORY:$image_tag"
deployment=$HE_GPU_DEPLOYMENT
service=$HE_GPU_SERVICE

kubectl get namespace "$namespace" >/dev/null 2>&1 || kubectl create namespace "$namespace"

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $deployment
  namespace: $namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $deployment
  template:
    metadata:
      labels:
        app: $deployment
    spec:
      containers:
        - name: $deployment
          image: $image
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: $HE_SERVICE_PORT
          env:
            - name: MAX_ARTIFACT_BYTES
              value: "268435456"
            - name: MAX_REQUEST_BYTES
              value: "805306368"
            - name: HE_GPU_WORKER_TIMEOUT_SECONDS
              value: "600"
          resources:
            requests:
              cpu: "2"
              memory: 4Gi
              nvidia.com/gpu: "1"
            limits:
              cpu: "8"
              memory: 16Gi
              nvidia.com/gpu: "1"
          startupProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 10
            failureThreshold: 60
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: $service
  namespace: $namespace
spec:
  selector:
    app: $deployment
  ports:
    - name: http
      port: $HE_SERVICE_PORT
      targetPort: http
YAML

kubectl -n "$namespace" rollout status "deployment/$deployment" \
  --timeout=15m

echo "GPU evaluator: http://$service:$HE_SERVICE_PORT"
