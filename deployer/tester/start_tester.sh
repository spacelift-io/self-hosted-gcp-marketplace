#!/bin/bash
#
# Runs the tester of a test install (DEPLOY_MODE=test). deploy.sh calls it
# after the app is ready.
#
# The tester is a Pod with the annotation marketplace.cloud.google.com/verification:
# test. It runs this same deployer image with check_placeholder.sh, under the
# deployer's service account, which can read the namespace. Google's
# run_tester.py applies the Pod, waits for it to finish and prints its log; a
# failed Pod fails the deploy, and with it `mpdev verify`.
#
# The Application owns the Pod, so deleting the app removes it. Like every Pod
# of the app, it has Google's tracking label (the same value as in the chart's
# values.yaml) and resource requests and limits.

set -euo pipefail

: "${NAME:?}" "${NAMESPACE:?}"

# The deployer runs as a Job Pod: its hostname is the Pod name.
self_pod="$(kubectl get pod "${HOSTNAME}" --namespace="${NAMESPACE}" --output=json)"
image="$(jq -r '.spec.containers[0].image' <<<"${self_pod}")"
service_account="$(jq -r '.spec.serviceAccountName' <<<"${self_pod}")"

app_uid="$(kubectl get "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --output=jsonpath='{.metadata.uid}')"
app_api_version="$(kubectl get "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --output=jsonpath='{.apiVersion}')"

manifest="$(mktemp --suffix=.yaml)"
cat >"${manifest}" <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}-tester
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${NAME}
    app.kubernetes.io/component: tester
    goog-partner-solution: isol_plb32_001kf00001dgv6liav_j4ogkpsbgbi4elkodchyxrpwapwswpd
  annotations:
    marketplace.cloud.google.com/verification: test
  ownerReferences:
    - apiVersion: ${app_api_version}
      kind: Application
      name: ${NAME}
      uid: ${app_uid}
      blockOwnerDeletion: true
spec:
  restartPolicy: Never
  serviceAccountName: ${service_account}
  containers:
    - name: tester
      image: ${image}
      command: ["/bin/check_placeholder.sh"]
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi
      env:
        - name: NAME
          value: ${NAME}
        - name: NAMESPACE
          value: ${NAMESPACE}
YAML

# mpdev collects the tester's log by this prefix, as with Google's own script.
run_tester.py --namespace "${NAMESPACE}" --manifest "${manifest}" --timeout "${TESTER_TIMEOUT:-300}" \
  | awk '{print "SMOKE_TEST "$0}'
