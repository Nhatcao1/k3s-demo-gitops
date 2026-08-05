#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"

usage() {
  echo "Usage: $0 <simple|serial|all>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT HUP INT TERM

run_example() {
  example=$1
  case "$example" in
    simple|serial) ;;
    *) usage ;;
  esac

  job="he-fides-$example"
  template="$script_dir/k8s/$example-job.yaml"
  rendered="$render_dir/$example-job.yaml"

  export HE_NAMESPACE HE_FIDES_EXAMPLES_IMAGE
  python3 "$repo_dir/scripts/render-he-yaml.py" "$template" > "$rendered"

  he_kubectl get namespace "$HE_NAMESPACE" >/dev/null 2>&1 || \
    he_kubectl create namespace "$HE_NAMESPACE"
  he_kubectl -n "$HE_NAMESPACE" delete job "$job" \
    --ignore-not-found >/dev/null
  he_kubectl create -f "$rendered"

  if ! he_kubectl -n "$HE_NAMESPACE" wait \
    --for=condition=complete "job/$job" --timeout=60m; then
    he_kubectl -n "$HE_NAMESPACE" get pod -l "app=$job" -o wide || true
    he_kubectl -n "$HE_NAMESPACE" describe "job/$job" || true
    he_kubectl -n "$HE_NAMESPACE" logs "job/$job" || true
    return 1
  fi

  he_kubectl -n "$HE_NAMESPACE" logs "job/$job"
}

case "$1" in
  simple|serial)
    run_example "$1"
    ;;
  all)
    for example in simple serial; do
      run_example "$example"
    done
    ;;
  *)
    usage
    ;;
esac
