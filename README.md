# self-hosted-gcp-marketplace

Google Cloud Marketplace listing for Spacelift Self-Hosted on GKE: the deployer image, the wrapper Helm chart and the install guide.

Spacelift Self-Hosted on Marketplace is "bring your own license": you get a license and registry credentials from Spacelift, and the Spacelift images are pulled from `oci.spacelift.io`.

## How the install works

1. The customer runs the Spacelift Terraform module for GCP ([terraform-google-spacelift-selfhosted](https://github.com/spacelift-io/terraform-google-spacelift-selfhosted)). It creates the GKE cluster, Cloud SQL, the Cloud Storage buckets and the IP addresses.
2. The customer creates a Kubernetes service account annotated for Workload Identity, installs cert-manager, and fills in the Marketplace form with the Terraform outputs, the license and the registry credentials.
3. Marketplace runs the deployer image as a Job in the cluster. The deployer installs the `spacelift-mp` chart with `helm upgrade --install`, so the app is a regular Helm release.
4. Later versions are installed with `helm upgrade`.

Without a license, the deployer installs only a placeholder: the Application resource and a ConfigMap.

## Layout

```
deployer/
  Dockerfile             the deployer image, on Google's deployer_helm base image
  schema.yaml            the Marketplace install form
  deploy.sh              the install script (replaces Google's /bin/deploy.sh)
  deploy_with_tests.sh   the test install that `mpdev verify` runs
  bin/spacelift_mp.py    maps the form to chart values; blocks downgrades
  chart/spacelift-mp/    wrapper chart around spacelift-self-hosted
  test/                  install forms with fake values for local checks
```

## Development

Needs Helm 4, Python 3 with PyYAML, and Docker.

```shell
make test     # unit tests, helm lint, render the chart with and without a license
make build    # build the deployer image for linux/amd64
```

Pulling the base image from `gcr.io` needs a Google login: `gcloud auth configure-docker gcr.io`.

## Versions

The version of a release follows the Spacelift Self-Hosted version it installs, without the `v` (`7.2.0`). A change to the deployer alone adds `-gcp.N` (`7.2.0-gcp.1`). The version is set in `deployer/chart/spacelift-mp/Chart.yaml`.

## License

[MIT](LICENSE)
