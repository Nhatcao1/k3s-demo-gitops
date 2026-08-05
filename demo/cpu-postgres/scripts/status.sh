#!/bin/sh
set -eu

namespace=he-dev

kubectl -n "$namespace" get statefulset,pod,job \
  -l app.kubernetes.io/part-of=cpu-postgres-demo -o wide

echo
echo "Recent demo Job logs:"
for job_name in $(kubectl -n "$namespace" get jobs \
  -l app.kubernetes.io/part-of=cpu-postgres-demo \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  echo "job/$job_name"
  kubectl -n "$namespace" logs "job/$job_name" --all-containers=true || true
done
