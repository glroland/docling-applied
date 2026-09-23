IMAGE    ?= quay.io/<your-org>/docling-event-driven-example:0.1.0
NAMESPACE ?= docling

PIP := $(if $(shell command -v uv 2>/dev/null),uv pip,pip)

.PHONY: install build push deploy undeploy test

install:
	$(PIP) install --upgrade -r requirements-dev.txt

build:
	podman build --platform linux/amd64 -f Containerfile -t $(IMAGE) .

push:
	podman push $(IMAGE)

deploy:
	helm upgrade --install docling-eventing deploy/helm -n $(NAMESPACE) --create-namespace \
		--set image.repository=$(shell echo $(IMAGE) | cut -d: -f1) \
		--set image.tag=$(shell echo $(IMAGE) | cut -d: -f2)

undeploy:
	helm uninstall docling-eventing -n $(NAMESPACE)

test:
	pytest tests/ -v
