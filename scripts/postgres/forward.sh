#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

case "$HE_POSTGRES_FORWARD_ADDRESS" in
  ""|*[[:space:],]*)
    echo "HE_POSTGRES_FORWARD_ADDRESS must be one IP address without commas." >&2
    exit 2
    ;;
esac

echo "Forwarding PostgreSQL on $HE_POSTGRES_FORWARD_ADDRESS:$HE_POSTGRES_LOCAL_PORT"
echo "Database/user are stored in Secret $HE_POSTGRES_SECRET; the password is not printed."
echo "Keep this terminal open; press Ctrl-C to stop forwarding."

he_kubectl -n "$HE_NAMESPACE" port-forward \
  --address "$HE_POSTGRES_FORWARD_ADDRESS" \
  "service/$HE_POSTGRES_SERVICE" \
  "$HE_POSTGRES_LOCAL_PORT:$HE_POSTGRES_PORT"
