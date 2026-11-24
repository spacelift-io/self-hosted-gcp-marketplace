# Deployer image for the Spacelift Self-Hosted listing on Google Cloud Marketplace.
#
# Marketplace runs this image as a Job in the customer's cluster. It installs
# the spacelift-mp chart with Helm, so the app is a regular Helm release that
# can be upgraded later with `helm upgrade`.

# Google's Helm deployer base image: Google's helper scripts, kubectl, Python.
# Pinned by tag and digest, because Google moves `latest` often.
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm:13.0.17@sha256:e2f38bc77f3ab3ce8da9d7e2befe793210c8bf2ea4e8a8ce1a5cd3d55db3d008

# The base image installs the newest Helm release at build time. Replace it
# with a pinned, checksum-verified version.
ARG HELM_VERSION=v4.3.2
ARG HELM_SHA256=d1c0278d46beab79582d7e50f5b3dc206944ba8e577cde618513fd07daa53983
RUN curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && echo "${HELM_SHA256}  /tmp/helm.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/helm.tar.gz -C /tmp linux-amd64/helm linux-amd64/LICENSE \
    && install -m 0755 /tmp/linux-amd64/helm "$(command -v helm)" \
    && mkdir -p /usr/share/doc/spacelift-mp \
    && mv /tmp/linux-amd64/LICENSE /usr/share/doc/spacelift-mp/Apache-2.0.txt \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
    && helm version

# Licences: ours for the files below, and notices for the tools we ship.
COPY LICENSE /usr/share/doc/spacelift-mp/LICENSE
COPY deployer/THIRD_PARTY_NOTICES /usr/share/doc/spacelift-mp/THIRD_PARTY_NOTICES

# The wrapper chart with its dependency (the spacelift-self-hosted chart)
# vendored in, so the install doesn't download anything from a Helm repo.
COPY deployer/chart/spacelift-mp /data/chart/spacelift-mp
# Temporary, see the script: allows `global` in the dependency's values schema.
COPY deployer/hack/allow-global-in-chart-schema.py /tmp/allow-global-in-chart-schema.py
RUN helm repo add spacelift https://downloads.spacelift.io/helm \
    && helm dependency build /data/chart/spacelift-mp \
    && helm repo remove spacelift \
    && python3 /tmp/allow-global-in-chart-schema.py /data/chart/spacelift-mp/charts/spacelift-self-hosted-*.tgz \
    && rm /tmp/allow-global-in-chart-schema.py

# The install form. The release version is filled in at build time.
ARG VERSION
COPY deployer/schema.yaml /data/schema.yaml
RUN test -n "${VERSION}" \
    && sed -i "s/__VERSION__/${VERSION}/g" /data/schema.yaml \
    && grep -q "publishedVersion: \"${VERSION}\"" /data/schema.yaml

# Our install scripts replace Google's. The ENTRYPOINT of the base image stays
# as it is: it runs /bin/deploy.sh.
COPY deployer/deploy.sh /bin/deploy.sh
COPY deployer/deploy_with_tests.sh /bin/deploy_with_tests.sh
RUN chmod 0755 /bin/deploy.sh /bin/deploy_with_tests.sh
