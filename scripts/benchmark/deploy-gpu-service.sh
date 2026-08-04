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
image="docker.io/dockerboi99/he_k8s:$image_tag"

kubectl get namespace "$namespace" >/dev/null

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: he-evaluator-gpu
  namespace: $namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: he-evaluator-gpu
  template:
    metadata:
      labels:
        app: he-evaluator-gpu
    spec:
      containers:
        - name: he-evaluator-gpu
          image: $image
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 8080
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
  name: he-evaluator-gpu
  namespace: $namespace
spec:
  selector:
    app: he-evaluator-gpu
  ports:
    - name: http
      port: 8080
      targetPort: http
YAML

kubectl -n "$namespace" rollout status deployment/he-evaluator-gpu \
  --timeout=15m

echo "GPU evaluator: http://he-evaluator-gpu:8080"
