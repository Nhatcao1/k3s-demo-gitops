#!/bin/sh

# Reject the known moving tags that previously returned stale registry-mirror
# content. Immutable commit tags and sha256 digests are accepted.
he_require_immutable_benchmark_image() {
  benchmark_image=$1
  benchmark_purpose=$2
  case "$benchmark_image" in
    ""|*[[:space:]]*)
      echo "$benchmark_purpose image is empty or invalid." >&2
      return 1
      ;;
    *:latest|*:cpu-latest|*:gpu-latest)
      echo "$benchmark_purpose refuses moving image tag: $benchmark_image" >&2
      echo "Deploy an immutable cpu-<commit> tag or provide an immutable override." >&2
      return 1
      ;;
  esac
}

# Select one of the two comparison-data PVCs from the requested profile group.
# The billion-range profiles never share storage with the bounded profiles.
he_select_comparison_data_volume() {
  he_data_uses_stress=false
  for he_data_argument in "$@"; do
    case "$he_data_argument" in
      stress|stress_positive_integer_1b|stress_negative_integer_1b)
        he_data_uses_stress=true
        ;;
    esac
  done

  if [ "$he_data_uses_stress" = "true" ]; then
    HE_COMPARE_DATA_PVC=$HE_STRESS_DATA_PVC
    HE_COMPARE_DATA_STORAGE=$HE_STRESS_DATA_STORAGE
    HE_COMPARE_DATA_PROFILE_GROUP=stress
    HE_COMPARE_DATA_PREPARE_GROUP=stress
  else
    HE_COMPARE_DATA_PVC=$HE_NORMAL_DATA_PVC
    HE_COMPARE_DATA_STORAGE=$HE_NORMAL_DATA_STORAGE
    HE_COMPARE_DATA_PROFILE_GROUP=normal
    HE_COMPARE_DATA_PREPARE_GROUP=all
  fi
  export HE_COMPARE_DATA_PVC HE_COMPARE_DATA_STORAGE
  export HE_COMPARE_DATA_PROFILE_GROUP HE_COMPARE_DATA_PREPARE_GROUP
}

# Delete one benchmark Job and wait until its Pod no longer holds the RWO PVC.
he_delete_benchmark_job() {
  benchmark_namespace=$1
  benchmark_job=$2
  benchmark_job_name=${benchmark_job#*/}

  he_kubectl -n "$benchmark_namespace" delete "$benchmark_job" \
    --ignore-not-found --cascade=foreground --wait=true --timeout=5m \
    >/dev/null
  he_kubectl -n "$benchmark_namespace" wait --for=delete pod \
    -l "job-name=$benchmark_job_name" --timeout=2m >/dev/null 2>&1 || true
}

# Preserve completed/failed Jobs for log recovery. Refuse to compete only with
# an active Job because the comparison-data PVC is intentionally RWO.
he_prepare_benchmark_pvc() {
  benchmark_namespace=$1
  active_jobs=""

  for benchmark_selector in \
    "app=he-comparison-data" \
    "app=he-operation-comparison"; do
    benchmark_jobs=$(he_kubectl -n "$benchmark_namespace" get jobs \
      -l "$benchmark_selector" -o name 2>/dev/null || true)
    for benchmark_job in $benchmark_jobs; do
      benchmark_conditions=$(he_kubectl -n "$benchmark_namespace" get \
        "$benchmark_job" \
        -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}')
      case "$benchmark_conditions" in
        *Complete=True*|*Failed=True*)
          :
          ;;
        *)
          active_jobs="$active_jobs $benchmark_job"
          ;;
      esac
    done
  done

  if [ -n "$active_jobs" ]; then
    echo "The RWO benchmark PVC is already used by an active Job:$active_jobs" >&2
    echo "Wait for it, or delete that Job before starting another run." >&2
    return 1
  fi
}
