# Repo-root .env (see ../.env.example) — same file the root Makefile
# reads, so NAMESPACE/PODMAN stay consistent whether you deploy/build via
# `make deploy-event-driven-example`/`build-event-driven-example` at the
# root or `make deploy`/`build` here. Note IMAGE below is this
# Makefile's own knob, not derived from the root's REGISTRY/IMAGE_TAG —
# override it directly (`make build IMAGE=...`) if you need it to match.
# Silently skipped if absent; `?=` defaults below still apply.
-include $(CURDIR)/../.env

IMAGE    ?= quay.io/<your-org>/docling-event-driven-example:0.1.0
NAMESPACE ?= docling

# Container engine — override to `docker` via ../.env or the command
# line (`make build PODMAN=docker`) if you don't use Podman.
PODMAN ?= podman

PIP := $(if $(shell command -v uv 2>/dev/null),uv pip,pip)

.PHONY: install build push deploy undeploy test

install:
	$(PIP) install --upgrade -r requirements-dev.txt

build:
	$(PODMAN) build --platform linux/amd64 -f Containerfile -t $(IMAGE) .

push:
	$(PODMAN) push $(IMAGE)

deploy:
	helm upgrade --install docling-eventing deploy/helm -n $(NAMESPACE) --create-namespace \
		--set image.repository=$(shell echo $(IMAGE) | cut -d: -f1) \
		--set image.tag=$(shell echo $(IMAGE) | cut -d: -f2)

undeploy:
	helm uninstall docling-eventing -n $(NAMESPACE)

test:
	pytest tests/ -v
