#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to generate the initial database password." >&2
  exit 1
}

case "$HE_POSTGRES_DATABASE" in
  ""|*[!0-9A-Za-z_-]*)
    echo "HE_POSTGRES_DATABASE contains unsupported characters." >&2
    exit 2
    ;;
esac
case "$HE_POSTGRES_USER" in
  ""|*[!0-9A-Za-z_-]*)
    echo "HE_POSTGRES_USER contains unsupported characters." >&2
    exit 2
    ;;
esac

schema_dir="$repo_dir/postgres/schema"
postgres_template="$repo_dir/k8s/he-postgres.yaml"
schema_job_template="$repo_dir/k8s/he-postgres-schema-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"
postgres_yaml=$(mktemp)
schema_job_yaml=$(mktemp)
configmap_yaml=$(mktemp)
trap 'rm -f "$postgres_yaml" "$schema_job_yaml" "$configmap_yaml"' EXIT HUP INT TERM

he_kubectl get namespace "$HE_NAMESPACE" >/dev/null 2>&1 || \
  he_kubectl create namespace "$HE_NAMESPACE"

# Preserve an existing password and database identity. HE_POSTGRES_PASSWORD is
# only used when the Secret is created for the first time.
if ! he_kubectl -n "$HE_NAMESPACE" get secret "$HE_POSTGRES_SECRET" >/dev/null 2>&1; then
  postgres_password=${HE_POSTGRES_PASSWORD:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(36))')}
  he_kubectl -n "$HE_NAMESPACE" create secret generic "$HE_POSTGRES_SECRET" \
    --from-literal="POSTGRES_DB=$HE_POSTGRES_DATABASE" \
    --from-literal="POSTGRES_USER=$HE_POSTGRES_USER" \
    --from-literal="POSTGRES_PASSWORD=$postgres_password" >/dev/null
  unset postgres_password
  echo "Created PostgreSQL credential Secret: $HE_POSTGRES_SECRET"
else
  echo "Preserving existing PostgreSQL credential Secret: $HE_POSTGRES_SECRET"
fi

he_kubectl -n "$HE_NAMESPACE" create configmap "$HE_POSTGRES_SCHEMA_CONFIGMAP" \
  --from-file="$schema_dir" \
  --dry-run=client -o yaml > "$configmap_yaml"
he_kubectl apply -f "$configmap_yaml" >/dev/null

export HE_NAMESPACE HE_POSTGRES_IMAGE HE_POSTGRES_STATEFULSET
export HE_POSTGRES_SERVICE HE_POSTGRES_PVC HE_POSTGRES_SECRET
export HE_POSTGRES_SCHEMA_CONFIGMAP HE_POSTGRES_SCHEMA_JOB_PREFIX
export HE_POSTGRES_PORT HE_POSTGRES_STORAGE
export HE_POSTGRES_REQUEST_CPU HE_POSTGRES_REQUEST_MEMORY
export HE_POSTGRES_LIMIT_CPU HE_POSTGRES_LIMIT_MEMORY

python3 "$renderer" "$postgres_template" > "$postgres_yaml"
python3 "$renderer" "$schema_job_template" > "$schema_job_yaml"

he_kubectl apply -f "$postgres_yaml"
he_kubectl -n "$HE_NAMESPACE" rollout status \
  "statefulset/$HE_POSTGRES_STATEFULSET" --timeout=10m

schema_job=$(he_kubectl create -f "$schema_job_yaml" -o name)
if ! he_kubectl -n "$HE_NAMESPACE" wait --for=condition=complete \
  "$schema_job" --timeout="$HE_POSTGRES_SCHEMA_TIMEOUT"; then
  he_kubectl -n "$HE_NAMESPACE" logs "$schema_job" --all-containers=true || true
  he_kubectl -n "$HE_NAMESPACE" describe "$schema_job" || true
  exit 1
fi
he_kubectl -n "$HE_NAMESPACE" logs "$schema_job"

echo "PostgreSQL is ready at $HE_POSTGRES_SERVICE:$HE_POSTGRES_PORT inside namespace $HE_NAMESPACE."
echo "External access: ./scripts/postgres/forward.sh"
