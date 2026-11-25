#!/bin/bash
#
# Installs Spacelift Self-Hosted from the Marketplace install form.
#
# Replaces /bin/deploy.sh of Google's deployer_helm image. Google's script
# renders the chart with `helm template` and applies it with kubectl. This one
# runs `helm upgrade --install`, so the app is a regular Helm release that the
# customer can upgrade with `helm upgrade` later.
#
# Steps:
#   1. read the form;
#   2. hand the Application, which Marketplace created, over to Helm;
#   3. helm upgrade --install; the chart stops a downgrade
#      (chart/spacelift-mp/templates/checks.yaml);
#   4. make the Application own every object of the release, and Helm's
#      release Secrets, so deleting the app removes everything;
#   5. mark the Application as ready and remove the deployer's service account.
#
# DEPLOY_MODE=test (set by deploy_with_tests.sh) also waits for the app to be
# ready.

set -euo pipefail

CHART_DIR=/data/chart/spacelift-mp
DEPLOY_MODE="${DEPLOY_MODE:-install}"

NAME="$(/bin/print_config.py --xtype NAME --values_mode raw)"
NAMESPACE="$(/bin/print_config.py --xtype NAMESPACE --values_mode raw)"
export NAME NAMESPACE

STEP="startup"
handle_failure() {
  code=$?
  echo "ERROR: the deployer failed at step \"${STEP}\" (exit code ${code})" >&2
  patch_assembly_phase.sh --status="Failed" || true
  exit "${code}"
}
trap handle_failure EXIT

echo "Deploying Spacelift as \"${NAME}\" in namespace \"${NAMESPACE}\""

STEP="read the form"
app_uid="$(kubectl get "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --output=jsonpath='{.metadata.uid}')"
app_api_version="$(kubectl get "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --output=jsonpath='{.apiVersion}')"
/bin/expand_config.py --values_mode raw --app_uid "${app_uid}"

# The form is a values file of the chart: its field names are value paths.
work_dir="$(mktemp -d)"
form_values="${work_dir}/form.yaml"
/bin/print_config.py --output=yaml --values_mode expanded > "${form_values}"
version="$(/bin/print_published_version.py)"

# Name the spacelift-self-hosted chart's objects after the install:
# <name>-server, <name>-mqtt, ... Without it the chart adds "-spacelift" to a
# name that doesn't contain "spacelift". A values file can't do it: it has no
# templates.
helm_args=(--set-string "spacelift.fullnameOverride=${NAME}")
# The chart installs Spacelift on the condition installSpacelift, which must be
# a boolean, so the license can't be the condition itself.
# A separate assignment, so a failing python3 stops the script (set -e).
has_license="$(python3 -c 'import sys, yaml; f = yaml.safe_load(open(sys.argv[1])) or {}; print(bool((f.get("license") or {}).get("token")))' "${form_values}")"
if [[ "${has_license}" == "False" ]]; then
  echo "No license given: installing only the placeholder."
  helm_args+=(--set installSpacelift=false)
else
  # The form can't require these: the placeholder doesn't need them. Stop here
  # with the field names, before Helm changes anything.
  STEP="check the form"
  missing="$(python3 -c 'import sys, yaml
f = yaml.safe_load(open(sys.argv[1])) or {}
fields = ["encryption.rsaPrivateKey", "registry.password"]
def get(path):
    v = f
    for k in path.split("."):
        v = (v or {}).get(k)
    return v
print(", ".join(p for p in fields if not get(p)))' "${form_values}")"
  if [[ -n "${missing}" ]]; then
    echo "ERROR: a license is given, but these form fields are empty: ${missing}. Deploy again with them filled in." >&2
    exit 1
  fi
fi

STEP="hand the Application over to Helm"
kubectl annotate "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --overwrite \
  "meta.helm.sh/release-name=${NAME}" \
  "meta.helm.sh/release-namespace=${NAMESPACE}"
kubectl label "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --overwrite \
  "app.kubernetes.io/managed-by=Helm"
# Marketplace creates the Application with the selector
# `matchLabels: app.kubernetes.io/name=<name>`. The Spacelift chart sets its own
# value in that label, so with it the Application would select none of the
# Spacelift objects. The chart's selector uses app.kubernetes.io/instance.
if [[ -n "$(kubectl get "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --output=jsonpath='{.spec.selector.matchLabels}')" ]]; then
  kubectl patch "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --type json \
    --patch '[{"op": "remove", "path": "/spec/selector/matchLabels"}]'
fi

STEP="helm upgrade --install"
# --force-conflicts: Marketplace created the Application with fields that the
# chart also sets. Helm applies server-side and takes those fields over.
helm upgrade --install "${NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --force-conflicts \
  --values "${form_values}" \
  "${helm_args[@]}"
rm -rf "${work_dir}"

STEP="set the owner of the release objects"
owner_patch="$(printf '{"metadata":{"ownerReferences":[{"apiVersion":"%s","kind":"Application","name":"%s","uid":"%s","blockOwnerDeletion":true}]}}' \
  "${app_api_version}" "${NAME}" "${app_uid}")"
{
  helm get manifest "${NAME}" --namespace "${NAMESPACE}" \
    | kubectl get --namespace "${NAMESPACE}" --filename - --output name
  # Helm keeps every revision, with the form values, in these Secrets.
  kubectl get secrets --namespace "${NAMESPACE}" --selector "owner=helm,name=${NAME}" --output name
} | grep -v '^application\.app\.k8s\.io/' | while read -r object; do
  kubectl patch "${object}" --namespace "${NAMESPACE}" --type merge --patch "${owner_patch}" >/dev/null
  echo "  owned by the Application: ${object}"
done

STEP="mark the Application as ready"
kubectl patch "applications.app.k8s.io/${NAME}" --namespace="${NAMESPACE}" --type merge \
  --patch "{\"spec\":{\"descriptor\":{\"version\":\"${version}\"}}}" >/dev/null
patch_assembly_phase.sh --status="Success"

if [[ "${DEPLOY_MODE}" == "test" ]]; then
  STEP="wait for the app to be ready"
  wait_for_ready.py --name "${NAME}" --namespace "${NAMESPACE}" --timeout "${WAIT_FOR_READY_TIMEOUT:-300}"
fi

STEP="remove the deployer's service account"
clean_iam_resources.sh

trap - EXIT
echo "Done: Spacelift ${version} is deployed as Helm release \"${NAME}\"."
