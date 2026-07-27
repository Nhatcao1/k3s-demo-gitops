#!/bin/sh
set -eu

echo "=== Nodes ==="
kubectl get nodes -o wide

echo "=== Argo CD Applications ==="
kubectl get applications -n argocd

echo "=== Development ==="
kubectl get all,pvc,ingress -n counter-dev -o wide

echo "=== Production ==="
kubectl get all,pvc,ingress -n counter-prod -o wide
