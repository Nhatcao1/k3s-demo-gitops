#!/bin/sh

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

# Remove completed/failed Jobs left by older scripts. Refuse to compete with
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
          echo "Removing finished benchmark $benchmark_job to release the PVC."
          he_delete_benchmark_job "$benchmark_namespace" "$benchmark_job"
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
