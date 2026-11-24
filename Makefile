# Local build and checks for the Marketplace deployer.
#
#   make test     lint the chart, then render it with and without a license
#   make build    build the deployer image for linux/amd64
#
# Needs: helm 4, python3 with PyYAML (for the render checks), docker (for build).

CHART    := deployer/chart/spacelift-mp
VERSION  ?= $(shell sed -n 's/^version: //p' $(CHART)/Chart.yaml)
REGISTRY ?= us-docker.pkg.dev/spacelift-public/spacelift-gcp-kubernetes-byol
DEPLOYER_IMAGE ?= $(REGISTRY)/deployer:$(VERSION)
PYTHON   ?= python3
BUILD    := build

.PHONY: test deps lint template build

test: lint template

# The second line is temporary, see the script.
deps:
	helm dependency build $(CHART)
	$(PYTHON) deployer/hack/allow-global-in-chart-schema.py $(CHART)/charts/spacelift-self-hosted-*.tgz

# The flags deploy.sh adds to the form: fullnameOverride is the install name,
# and installSpacelift is false without a license.
form_name = $$(sed -n 's/^name: //p' $(1))
deploy_flags = --set-string spacelift.fullnameOverride=$(call form_name,$(1)) \
	$$($(PYTHON) -c 'import sys, yaml; f = yaml.safe_load(open(sys.argv[1])) or {}; print("" if (f.get("license") or {}).get("token") else "--set installSpacelift=false")' $(1))

# Renders the chart the way deploy.sh calls Helm.
$(BUILD)/%.yaml: deployer/test/form-%.yaml deps
	@mkdir -p $(BUILD)
	helm template $(call form_name,$<) $(CHART) --namespace $$(sed -n 's/^namespace: //p' $<) \
		--values $< $(call deploy_flags,$<) > $@

# The full form with the ClusterIssuer left empty.
$(BUILD)/no-issuer.yaml: deployer/test/form-full.yaml deps
	@mkdir -p $(BUILD)
	helm template spacelift $(CHART) --namespace spacelift \
		--values $< $(call deploy_flags,$<) --set ingress.clusterIssuer= > $@

# helm lint renders the chart as the release "test-release".
lint: deps
	helm lint $(CHART) --namespace spacelift \
		--values deployer/test/form-full.yaml --set-string spacelift.fullnameOverride=test-release

template: $(BUILD)/full.yaml $(BUILD)/renamed.yaml $(BUILD)/placeholder.yaml $(BUILD)/no-issuer.yaml
	@echo "Without a license: only the Application and the placeholder ConfigMap."
	@test "$$(grep -c '^kind:' $(BUILD)/placeholder.yaml)" = 2
	@grep -q '^kind: ConfigMap' $(BUILD)/placeholder.yaml
	@! grep -q 'oci.spacelift.io' $(BUILD)/placeholder.yaml
	@echo "  ok"
	@echo "With a license:"
	@$(PYTHON) deployer/test/check_render.py --form deployer/test/form-full.yaml --rendered $(BUILD)/full.yaml
	@echo "With a license, under a name without \"spacelift\" in it:"
	@$(PYTHON) deployer/test/check_render.py --form deployer/test/form-renamed.yaml --rendered $(BUILD)/renamed.yaml
	@echo "Without a ClusterIssuer: no cert-manager annotations on the Ingresses."
	@test "$$(grep -c 'kubernetes.io/ingress.global-static-ip-name' $(BUILD)/no-issuer.yaml)" = 2
	@! grep -qE 'cert-manager.io/cluster-issuer|http01-edit-in-place' $(BUILD)/no-issuer.yaml
	@echo "  ok"
	@echo "Without fullnameOverride = the install name: the chart refuses to render."
	@! helm template sl-prod $(CHART) --namespace tools --values deployer/test/form-renamed.yaml >/dev/null 2>$(BUILD)/no-fullname.err
	@grep -q 'must be the install name' $(BUILD)/no-fullname.err
	@echo "  ok"

build:
	docker buildx build --platform linux/amd64 \
		--build-arg VERSION=$(VERSION) \
		--file deployer/Dockerfile \
		--tag $(DEPLOYER_IMAGE) \
		--load .
