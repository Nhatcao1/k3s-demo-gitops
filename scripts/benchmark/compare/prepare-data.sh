#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
. "$repo_dir/config/he-lab.env"
. "$repo_dir/scripts/lib/kubectl.sh"
. "$repo_dir/scripts/lib/benchmark-jobs.sh"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to render the data preparation Job." >&2
  exit 1
}
command -v gzip >/dev/null 2>&1 || {
  echo "gzip is required to package the generator code." >&2
  exit 1
}

namespace=$HE_NAMESPACE
job_timeout=${BENCH_JOB_TIMEOUT_SECONDS:-43200}
run_id=${RUN_ID:-"$(date -u +%Y%m%d%H%M%S)"}
job_name="he-comparison-data-$run_id"
pvc_template="$repo_dir/k8s/he-comparison-data-pvc.yaml"
job_template="$repo_dir/k8s/he-comparison-data-job.yaml"
renderer="$repo_dir/scripts/render-he-yaml.py"

temporary_dir=$(mktemp -d)
job_created=false
cleanup() {
  cleanup_status=$?
  trap - EXIT HUP INT TERM
  if [ "$job_created" = "true" ]; then
    he_delete_benchmark_job "$namespace" "job/$job_name" || true
  fi
  rm -rf "$temporary_dir"
  exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
arguments_file="$temporary_dir/arguments.txt"
pvc_yaml="$temporary_dir/pvc.yaml"
job_yaml="$temporary_dir/job.yaml"

if [ "$#" -eq 0 ]; then
  set -- --count 1000000 --data-profiles all --seed 42
fi
he_select_comparison_data_volume "$@"
printf '%s\n' "$@" > "$arguments_file"
gzip -c "$script_dir/data_profiles.py" > "$temporary_dir/data_profiles.py.gz"
gzip -c "$script_dir/generate_data.py" > "$temporary_dir/generate_data.py.gz"

data_image=${HE_COMPARE_DATA_IMAGE:-}
if [ -z "$data_image" ]; then
  data_image=$(he_kubectl -n "$namespace" get \
    "deployment/$HE_CPU_DEPLOYMENT" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
fi
he_require_immutable_benchmark_image "$data_image" "Stress data generator"
echo "Data generator image: $data_image"
echo "Comparison data PVC ($HE_COMPARE_DATA_PROFILE_GROUP): $HE_COMPARE_DATA_PVC"

HE_COMPARE_DATA_JOB_NAME=$job_name
HE_COMPARE_DATA_IMAGE=$data_image
HE_COMPARE_DATA_JOB_TIMEOUT_SECONDS=$job_timeout
export HE_NAMESPACE HE_COMPARE_DATA_PVC HE_COMPARE_DATA_STORAGE
export HE_COMPARE_DATA_JOB_NAME HE_COMPARE_DATA_IMAGE
export HE_COMPARE_DATA_JOB_TIMEOUT_SECONDS
export HE_COMPARE_DATA_REQUEST_CPU HE_COMPARE_DATA_REQUEST_MEMORY
export HE_COMPARE_DATA_LIMIT_CPU HE_COMPARE_DATA_LIMIT_MEMORY
export HE_COMPARE_DATA_TMP_STORAGE HE_COMPARE_JOB_TTL_SECONDS

python3 "$renderer" "$pvc_template" > "$pvc_yaml"
python3 "$renderer" "$job_template" > "$job_yaml"
he_kubectl apply -f "$pvc_yaml"
he_kubectl -n "$namespace" wait \
  --for=jsonpath='{.status.phase}'=Bound "pvc/$HE_COMPARE_DATA_PVC" \
  --timeout=5m
he_prepare_benchmark_pvc "$namespace"

he_kubectl -n "$namespace" create configmap he-comparison-data-code \
  --from-file=data_profiles.py.gz="$temporary_dir/data_profiles.py.gz" \
  --from-file=generate_data.py.gz="$temporary_dir/generate_data.py.gz" \
  --from-file=arguments.txt="$arguments_file" \
  --dry-run=client -o yaml |
  he_kubectl apply -f -

he_kubectl -n "$namespace" delete "job/$job_name" --ignore-not-found >/dev/null
he_kubectl create -f "$job_yaml"
job_created=true
if ! he_kubectl -n "$namespace" wait \
  --for=condition=complete "job/$job_name" --timeout="${job_timeout}s"; then
  he_kubectl -n "$namespace" logs "job/$job_name" --all-containers=true || true
  he_kubectl -n "$namespace" describe "job/$job_name" || true
  exit 1
fi
he_kubectl -n "$namespace" logs "job/$job_name"
he_delete_benchmark_job "$namespace" "job/$job_name"
job_created=false
echo "Reusable benchmark data is ready in PVC $namespace/$HE_COMPARE_DATA_PVC."
