#!/bin/bash
#
# Runs Google's verification (`mpdev verify`) for a deployer image on a new
# kind cluster, then deletes the cluster. CI runs it on every pull request, and
# it works the same way on a laptop.
#
#   deployer/test/kind-verify.sh <local deployer image>
#
# Needs docker, kind and a login to gcr.io (`mpdev` and the deployer's base
# image come from gcr.io/cloud-marketplace-tools).
#
# `mpdev` sets `imagePullPolicy: Always` on the deployer Job, so loading the
# image into kind is not enough: the script starts a local registry next to the
# cluster. `mpdev` also rejects an image name with a port, so the cluster pulls
# the image by a port-less name that containerd maps to that registry.

set -euo pipefail

image="${1:?usage: $0 <local deployer image>}"

CLUSTER="${CLUSTER:-mp-verify}"
REGISTRY_PORT="${REGISTRY_PORT:-5056}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.35.0}"
MPDEV_IMAGE="${MPDEV_IMAGE:-gcr.io/cloud-marketplace-tools/k8s/dev@sha256:08be7a43a2d06d8991a7b1f0148cc4fcc386d92045b39fbb57511cead39ccca4}"
# Google's Application CRD, pinned to the last commit that changed it.
APP_CRD_URL="${APP_CRD_URL:-https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/7d32ea003d04d571f026a0b23c84fd5166586f53/crd/app-crd.yaml}"
# Keep the cluster after the run. The script doesn't touch ~/.kube/config;
# `kind export kubeconfig --name <cluster>` adds the cluster there.
KEEP_CLUSTER="${KEEP_CLUSTER:-false}"
# Where mpdev writes its logs (the deployer's and the tester's).
LOGS_DIR="${LOGS_DIR:-}"

registry="${CLUSTER}-registry"
registry_name="mp-registry.local"
work="$(mktemp -d)"

cleanup() {
  if [[ "${KEEP_CLUSTER}" != "true" ]]; then
    kind delete cluster --name "${CLUSTER}" --kubeconfig "${work}/kubeconfig" >/dev/null 2>&1 || true
    docker rm -f "${registry}" >/dev/null 2>&1 || true
  fi
  rm -rf "${work}"
}
trap cleanup EXIT

echo "--- Create the kind cluster ${CLUSTER}"
cat >"${work}/kind.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
EOF
kind create cluster --name "${CLUSTER}" --image "${KIND_NODE_IMAGE}" --config "${work}/kind.yaml" \
  --kubeconfig "${work}/kubeconfig" --wait 120s

echo "--- Start the local registry and point ${registry_name} at it"
docker run -d --restart=always --name "${registry}" -p "127.0.0.1:${REGISTRY_PORT}:5000" --network kind registry:2 >/dev/null
for node in $(kind get nodes --name "${CLUSTER}"); do
  docker exec "${node}" mkdir -p "/etc/containerd/certs.d/${registry_name}"
  docker exec -i "${node}" tee "/etc/containerd/certs.d/${registry_name}/hosts.toml" >/dev/null <<EOF
server = "http://${registry}:5000"
[host."http://${registry}:5000"]
  capabilities = ["pull", "resolve"]
EOF
done

echo "--- Push the deployer image"
tag="${image##*:}"
push_ref="localhost:${REGISTRY_PORT}/spacelift-mp/deployer:${tag}"
deployer_ref="${registry_name}/spacelift-mp/deployer:${tag}"
docker tag "${image}" "${push_ref}"
# mpdev reads the image through the host's Docker too, by the same name as the cluster.
docker tag "${image}" "${deployer_ref}"
# The registry may need a moment to start.
for attempt in 1 2 3 4 5; do
  docker push --quiet "${push_ref}" && break
  [[ "${attempt}" == 5 ]] && exit 1
  sleep 2
done

echo "--- Run mpdev verify"
logs="${LOGS_DIR:-${work}/logs}"
mkdir -p "${work}/kube" "${logs}"
kind get kubeconfig --name "${CLUSTER}" --internal >"${work}/kube/config"
mpdev() {
  # The same flags as Google's `mpdev` wrapper script, on the kind network.
  docker run --rm --init --platform linux/amd64 --network kind \
    --env DOCKER_API_VERSION=1.41 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${work}/kube:/mount/config/.kube" \
    -v "$(cd "${logs}" && pwd):/logs" \
    "${MPDEV_IMAGE}" "$@"
}
mpdev kubectl apply -f "${APP_CRD_URL}"
mpdev verify --deployer="${deployer_ref}"
