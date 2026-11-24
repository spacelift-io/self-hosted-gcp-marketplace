# Local build and checks for the Marketplace deployer.
#
#   make test     unit tests, then render the chart with and without a license
#   make build    build the deployer image for linux/amd64
#
# Needs: helm 4, python3 with PyYAML, docker (for build).

CHART    := deployer/chart/spacelift-mp
VERSION  ?= $(shell sed -n 's/^version: //p' $(CHART)/Chart.yaml)
REGISTRY ?= us-docker.pkg.dev/spacelift-public/spacelift-gcp-kubernetes-byol
DEPLOYER_IMAGE ?= $(REGISTRY)/deployer:$(VERSION)
PYTHON   ?= python3
BUILD    := build

.PHONY: test unit deps lint template build

test: unit lint template

unit:
	cd deployer/bin && $(PYTHON) -m unittest spacelift_mp_test.py

# The second line is temporary, see the script.
deps:
	helm dependency build $(CHART)
	$(PYTHON) deployer/hack/allow-global-in-chart-schema.py $(CHART)/charts/spacelift-self-hosted-*.tgz

# Renders the chart the way deploy.sh calls Helm: the form values, then the
# values spacelift_mp.py makes from the form.
$(BUILD)/%.yaml: deployer/test/form-%.yaml deps
	@mkdir -p $(BUILD)
	$(PYTHON) deployer/bin/spacelift_mp.py values --form $< > $(BUILD)/chart-values-$*.yaml
	helm template $$(sed -n 's/^name: //p' $<) $(CHART) --namespace $$(sed -n 's/^namespace: //p' $<) \
		--values $< --values $(BUILD)/chart-values-$*.yaml > $@

lint: deps
	@mkdir -p $(BUILD)
	$(PYTHON) deployer/bin/spacelift_mp.py values --form deployer/test/form-full.yaml > $(BUILD)/chart-values-lint.yaml
	helm lint $(CHART) --namespace spacelift \
		--values deployer/test/form-full.yaml --values $(BUILD)/chart-values-lint.yaml

template: $(BUILD)/full.yaml $(BUILD)/renamed.yaml $(BUILD)/placeholder.yaml
	@echo "Without a license: only the Application and the placeholder ConfigMap."
	@test "$$(grep -c '^kind:' $(BUILD)/placeholder.yaml)" = 2
	@grep -q '^kind: ConfigMap' $(BUILD)/placeholder.yaml
	@! grep -q 'oci.spacelift.io' $(BUILD)/placeholder.yaml
	@echo "  ok"
	@echo "With a license:"
	@$(PYTHON) deployer/test/check_render.py --form deployer/test/form-full.yaml --rendered $(BUILD)/full.yaml
	@echo "With a license, under a name without \"spacelift\" in it:"
	@$(PYTHON) deployer/test/check_render.py --form deployer/test/form-renamed.yaml --rendered $(BUILD)/renamed.yaml

build:
	docker buildx build --platform linux/amd64 \
		--build-arg VERSION=$(VERSION) \
		--file deployer/Dockerfile \
		--tag $(DEPLOYER_IMAGE) \
		--load .
