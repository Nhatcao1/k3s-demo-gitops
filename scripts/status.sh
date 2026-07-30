#!/bin/sh
set -eu

echo "=== Nodes ==="
kubectl get nodes -o wide

echo "=== Argo CD Applications ==="
kubectl get applications -n argocd

echo "=== HE Development ==="
kubectl get all,ingress -n he-dev -o wide
