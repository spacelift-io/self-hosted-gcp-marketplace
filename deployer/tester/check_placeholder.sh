#!/bin/bash
#
# The tester of a test install. Runs in the tester Pod (see start_tester.sh).
#
# A test install has no license, so the deployer installs only the placeholder
# ConfigMap. This checks that:
#   1. the ConfigMap exists and has the labels the Application selects by;
#   2. the Application owns it, so deleting the app removes it.

set -euo pipefail

: "${NAME:?}" "${NAMESPACE:?}"

fail() {
  echo "FAIL: $*"
  exit 1
}

configmap="${NAME}-placeholder"
echo "Checking ConfigMap ${configmap} in namespace ${NAMESPACE}"

json="$(kubectl get configmap "${configmap}" --namespace="${NAMESPACE}" --output=json)" \
  || fail "ConfigMap ${configmap} not found"

for label in app.kubernetes.io/name app.kubernetes.io/instance; do
  value="$(jq -r --arg l "${label}" '.metadata.labels[$l] // ""' <<<"${json}")"
  [[ "${value}" == "${NAME}" ]] || fail "label ${label} is \"${value}\", expected \"${NAME}\""
  echo "  ok: label ${label}=${value}"
done

app_uid="$(kubectl get "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --output=jsonpath='{.metadata.uid}')" \
  || fail "Application ${NAME} not found"
owner="$(jq -r --arg uid "${app_uid}" \
  '[.metadata.ownerReferences[]? | select(.kind == "Application" and .uid == $uid)] | length' <<<"${json}")"
[[ "${owner}" == "1" ]] || fail "ConfigMap ${configmap} is not owned by Application ${NAME}"
echo "  ok: owned by Application ${NAME}"

echo "PASS"
