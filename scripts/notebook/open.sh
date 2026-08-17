#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

token_base64=$(he_kubectl -n "$HE_NAMESPACE" get secret "$HE_NOTEBOOK_SECRET" \
  -o 'jsonpath={.data.token}')
token=$(printf '%s' "$token_base64" | base64 --decode)

echo "Open this URL in your browser:"
echo "http://127.0.0.1:$HE_NOTEBOOK_LOCAL_PORT/lab?token=$token"
echo "Keep this terminal open; press Ctrl-C to stop forwarding."

he_kubectl -n "$HE_NAMESPACE" port-forward \
  "service/$HE_NOTEBOOK_SERVICE" \
  "$HE_NOTEBOOK_LOCAL_PORT:$HE_NOTEBOOK_PORT"
