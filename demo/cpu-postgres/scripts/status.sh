#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "${DEMO_ENV_FILE:-$demo_dir/demo.env}"

kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" get statefulset,pod,job \
  -l app.kubernetes.io/part-of=cpu-postgres-demo -o wide

kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.scheme,s.status,s.valid_count,r.expected_sum,r.decrypted_sum,(r.decrypted_sum-r.expected_sum) AS sum_difference,r.expected_kpi_amount,r.decrypted_kpi_amount,(r.decrypted_kpi_amount-r.expected_kpi_amount) AS kpi_difference,s.updated_at FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT run_id,session_id,command,outcome,detail,started_at,finished_at FROM he_demo_job_runs ORDER BY run_id;"'
