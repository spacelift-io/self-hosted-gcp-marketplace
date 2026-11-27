# self-hosted-gcp-marketplace

Google Cloud Marketplace listing for Spacelift Self-Hosted on GKE: the deployer image, the wrapper Helm chart and the install guide.

Spacelift Self-Hosted on Marketplace is "bring your own license": you get a license and registry credentials from Spacelift, and the Spacelift images are pulled from `oci.spacelift.io`.

## How the install works

1. The customer runs the Spacelift Terraform module for GCP ([terraform-google-spacelift-selfhosted](https://github.com/spacelift-io/terraform-google-spacelift-selfhosted)), v3.3.0 or later. It creates the GKE cluster, Cloud SQL, the Cloud Storage buckets and the IP addresses, and outputs the values the form asks for.
2. The customer creates a Kubernetes service account annotated for Workload Identity, installs cert-manager, and fills in the Marketplace form with the Terraform outputs, the license and the registry credentials.
3. Marketplace runs the deployer image as a Job in the cluster. The deployer installs the `spacelift-mp` chart with `helm upgrade --install`, so the app is a regular Helm release.

The deployer makes the Application the owner of every object of the install, so deleting the app in the GKE console removes everything. This also covers what a failed install leaves behind. Objects created by a later `helm upgrade` run by hand don't get the owner yet.

Without a license, the deployer installs only a placeholder: the Application resource and a ConfigMap.

## Layout

```
deployer/
  Dockerfile             the deployer image, on Google's deployer_helm base image
  schema.yaml            the Marketplace install form
  deploy.sh              the install script (replaces Google's /bin/deploy.sh)
  deploy_with_tests.sh   the test install that `mpdev verify` runs
  chart/spacelift-mp/    wrapper chart around spacelift-self-hosted; renders the GKE Ingresses
  data-test/schema.yaml  test values for the form, used only by the test install
  tester/                the tester of the test install: checks the placeholder
  test/                  install forms with fake values for local checks
  hack/                  temporary build fixes, each one says when to remove it
```

## Development

Needs Helm 4, Python 3 with PyYAML (for the render checks), and Docker.

```shell
make test     # helm lint, render the chart with and without a license and check it
make build    # build the deployer image for linux/amd64
make verify   # run `mpdev verify` with the built image on the current cluster
make verify-kind  # the same on a new kind cluster, deleted after the run
```

`make verify` runs the same check as Google's verification: install with the test values and no license, run the tester, delete the app and check that nothing is left. It needs [`mpdev`](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/blob/master/docs/tool-prerequisites.md), the [Application CRD](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/blob/master/crd/app-crd.yaml) in the cluster, and the image pushed to a registry the cluster can pull from (`docker push` of the `make build` image).

`make verify-kind` needs only Docker and [kind](https://kind.sigs.k8s.io/): it creates a cluster with a local registry, installs the Application CRD, runs `mpdev verify` from its image and deletes the cluster (`KEEP_CLUSTER=true` keeps it).

Pulling the base image and `mpdev` from `gcr.io` needs a Google login: `gcloud auth configure-docker gcr.io`.

## CI

Every pull request runs `make test`. When the repo has a Google login set up for GitHub Actions (the `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` variables, for Workload Identity Federation), it also runs `make build` and `make verify-kind`.

[Renovate](https://docs.renovatebot.com/) (`.github/renovate.json`, run by `.github/workflows/renovate.yaml`) opens a pull request when a new `spacelift-self-hosted` chart is released. The pull request moves the chart dependency, `Chart.lock`, `version` and `appVersion` to the new Self-Hosted version, and Renovate merges it once the checks pass. It also keeps the GitHub Actions up to date. Google's images on `gcr.io/cloud-marketplace-tools` are updated by hand.

## Versions

The version of a release follows the Spacelift Self-Hosted version it installs, without the `v` (`7.2.0`). A change to the deployer alone adds `-gcp.N` (`7.2.0-gcp.1`). The version is set in `deployer/chart/spacelift-mp/Chart.yaml`.

## License

[MIT](LICENSE)
