#!/bin/sh

# Central wrapper for every scripted kubectl call. TLS verification remains on
# by default. Set HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY=true only for a temporary
# lab cluster whose API certificate cannot yet be verified.
case "${HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY:-false}" in
  true|false) ;;
  *)
    echo "HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY must be true or false." >&2
    exit 2
    ;;
esac

he_kubectl() {
  if [ "${HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY:-false}" = "true" ]; then
    command kubectl --insecure-skip-tls-verify=true "$@"
  else
    command kubectl "$@"
  fi
}
