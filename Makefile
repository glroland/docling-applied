# Orchestrates smoke testing across every example in this repo.
#
# Conventions:
#   - All temp/output files land under target/ (this Makefile creates
#     target/<example-name>/ per example). Nothing is ever written inside
#     an example's own subfolder.
#   - `make clean` removes target/ and nothing else.
#   - Test data always comes from samples/ at the repo root.
#   - Steps that need a live cluster or external service (deploy targets,
#     and a few test targets) check for the required tool/endpoint first
#     and print a clear "skipped" message instead of failing the whole
#     run when it's not available — useful for running this against
#     whatever subset of infrastructure you actually have up.
#
# Usage:
#   make help
#   make build            # prepare/compile/package everything that has a build step
#   make test             # smoke-test everything (uses samples/, writes to target/)
#   make deploy            # deploy everything that has a deployable artifact
#   make clean             # rm -rf target/
#   make test-docling-serve-examples DOCLING_SERVE_URL=https://...
#
# Run `make help` for the full list of per-example targets.

# Every recipe with multiple shell statements uses explicit backslash
# line-continuation (one logical recipe line per Make rule) rather than
# .ONESHELL, since .ONESHELL requires GNU Make >= 3.82 and macOS still
# ships 3.81 by default.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT_DIR    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TARGET_DIR  := $(ROOT_DIR)/target
SAMPLES_DIR := $(ROOT_DIR)/samples

# Route all Python bytecode caches under target/, regardless of which
# example's scripts are running, so no __pycache__/ ever lands in a
# subfolder.
export PYTHONPYCACHEPREFIX := $(TARGET_DIR)/pycache

PODMAN ?= podman
HELM   ?= helm
OC     ?= oc

# Every example installs into one shared virtual environment under
# target/ (so `make clean` removes it, and nothing lands in a subfolder).
# It's pinned to the Python version Red Hat's RHOAI 3.5 package index
# publishes wheels for (see requirements.txt) — using a different local
# Python here is how you'd end up needing pip/uv to fall back off that
# index for docling itself, not just its platform-specific deps.
DOCLING_PYTHON_VERSION ?= 3.12
VENV_DIR    := $(TARGET_DIR)/venv
VENV_PYTHON := $(VENV_DIR)/bin/python3

UV := $(shell command -v uv 2>/dev/null)

PYTHON := $(VENV_PYTHON)
# uv's default index strategy commits to the first index that has *any*
# version of a package; requirements.txt's Red Hat index only ships Linux
# wheels, so on macOS/Windows that default would refuse to fall back to
# PyPI for things like pydantic-core. unsafe-best-match restores normal
# pip-like fallback behavior. Plain pip doesn't have that strict default
# (and doesn't understand this flag), so it's uv-only.
# `install` is baked in here (rather than left for call sites to append)
# since --python/--index-strategy are flags of `uv pip install`, not of
# the `uv pip` command group — they have to come after it.
ifneq ($(UV),)
PIP := uv pip install --python $(VENV_PYTHON) --index-strategy unsafe-best-match
else
PIP := $(VENV_PYTHON) -m pip install
endif

NAMESPACE ?= docling
IMAGE_TAG ?= 0.1.0
REGISTRY  ?= quay.io/<your-org>

# Optional live-infrastructure endpoints — unset by default, so the
# targets that need them skip cleanly instead of failing.
DOCLING_SERVE_URL   ?=
LLAMA_STACK_URL     ?=
PIPELINES_ENDPOINT  ?=

SAMPLE_STRUCTURED := $(SAMPLES_DIR)/structured.pdf
SAMPLE_SCANNED    := $(SAMPLES_DIR)/scanned.pdf
SAMPLE_HYBRID     := $(SAMPLES_DIR)/hybrid.pdf

EXAMPLES := simple-examples cli-examples docling-serve docling-serve-examples \
            batch-via-pipeline-example serverless-api-example \
            event-driven-example rag-via-ogx-example mcp-example

.PHONY: help clean install build test deploy \
        $(addprefix build-,$(EXAMPLES)) \
        $(addprefix test-,$(EXAMPLES)) \
        $(addprefix deploy-,$(EXAMPLES))

help:
	@echo "docling-applied — smoke test orchestration"
	@echo ""
	@echo "  make install   Install the central Docling pin (requirements.txt)"
	@echo "  make build     Prepare/compile every example that has a build step"
	@echo "  make test      Run every example's smoke test (writes to target/)"
	@echo "  make deploy    Deploy every example that has a deployable artifact"
	@echo "  make clean     Remove target/ (the only place this Makefile writes)"
	@echo ""
	@echo "Per-example targets: build-<name> / test-<name> / deploy-<name>, for:"
	@echo "  $(EXAMPLES)"
	@echo ""
	@echo "Live-infrastructure overrides (skipped cleanly when unset/unreachable):"
	@echo "  NAMESPACE=$(NAMESPACE)  DOCLING_SERVE_URL=  LLAMA_STACK_URL=  PIPELINES_ENDPOINT="
	@echo ""
	@echo "Uses 'uv pip' automatically when uv is on PATH, otherwise plain pip."

clean:
	rm -rf "$(TARGET_DIR)"
	@echo "Removed $(TARGET_DIR)"

# Creates the shared venv under target/ that every install/run target
# below depends on. Idempotent — skips creation if it already exists.
$(VENV_PYTHON):
	@mkdir -p "$(TARGET_DIR)"
	if [ -n "$(UV)" ]; then \
		echo "[venv] uv venv --python $(DOCLING_PYTHON_VERSION) $(VENV_DIR)"; \
		uv venv --python "$(DOCLING_PYTHON_VERSION)" "$(VENV_DIR)"; \
	else \
		v=$$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])'); \
		if [ "$$v" != "$(DOCLING_PYTHON_VERSION)" ]; then \
			echo "[venv] WARNING: system python3 is $$v, not $(DOCLING_PYTHON_VERSION)." >&2; \
			echo "[venv] Red Hat's package index only ships wheels for $(DOCLING_PYTHON_VERSION); without uv to fetch a matching interpreter, this may fail to resolve. Install uv, or a $(DOCLING_PYTHON_VERSION) interpreter yourself." >&2; \
		fi; \
		echo "[venv] python3 -m venv $(VENV_DIR)"; \
		python3 -m venv "$(VENV_DIR)"; \
	fi

# Installs the single source of truth for the Docling version used across
# every example (requirements.txt at the repo root). Each example's own
# requirements.txt pulls this in via `-r ../requirements.txt`, so running
# this once establishes the shared baseline before any per-example build.
install: $(VENV_PYTHON)
	@echo "[install] $(PIP) -r requirements.txt"
	$(PIP) -r requirements.txt

$(TARGET_DIR)/%:
	@mkdir -p "$@"

# ---------------------------------------------------------------------------
# Aggregate targets
# ---------------------------------------------------------------------------

build: $(addprefix build-,$(EXAMPLES))

test: $(addprefix test-,$(EXAMPLES))

deploy: $(addprefix deploy-,$(EXAMPLES))

# ---------------------------------------------------------------------------
# simple-examples — Docling SDK called directly, no build/deploy step
# ---------------------------------------------------------------------------

build-simple-examples: | $(VENV_PYTHON)
	@echo "[simple-examples] installing requirements"
	$(PIP) -q -r simple-examples/requirements.txt

test-simple-examples: build-simple-examples | $(TARGET_DIR)/simple-examples
	@echo "[simple-examples] converting samples with the Docling SDK"
	$(PYTHON) simple-examples/scripts/convert_pdf.py "$(SAMPLE_STRUCTURED)" "$(TARGET_DIR)/simple-examples"
	$(PYTHON) simple-examples/scripts/convert_pdf.py "$(SAMPLE_SCANNED)" "$(TARGET_DIR)/simple-examples"
	$(PYTHON) simple-examples/scripts/chunking.py "$(SAMPLE_HYBRID)" "$(TARGET_DIR)/simple-examples"

deploy-simple-examples:
	@echo "[simple-examples] not applicable — SDK scripts have no deployable artifact"

# ---------------------------------------------------------------------------
# cli-examples — the `docling` command-line tool, no Python required
# ---------------------------------------------------------------------------

build-cli-examples: | $(VENV_PYTHON)
	@echo "[cli-examples] installing requirements (docling, for the CLI it ships)"
	$(PIP) -q -r cli-examples/requirements.txt

test-cli-examples: build-cli-examples | $(TARGET_DIR)/cli-examples
	@echo "[cli-examples] converting samples with the docling CLI"
	PATH="$(VENV_DIR)/bin:$$PATH" bash cli-examples/scripts/convert_to_markdown.sh "$(SAMPLE_STRUCTURED)" "$(TARGET_DIR)/cli-examples"
	PATH="$(VENV_DIR)/bin:$$PATH" bash cli-examples/scripts/convert_scanned_with_ocr.sh "$(SAMPLE_SCANNED)" "$(TARGET_DIR)/cli-examples"
	PATH="$(VENV_DIR)/bin:$$PATH" bash cli-examples/scripts/chunk_document.sh "$(SAMPLE_HYBRID)" "$(TARGET_DIR)/cli-examples"

deploy-cli-examples:
	@echo "[cli-examples] not applicable — shell scripts have no deployable artifact"

# ---------------------------------------------------------------------------
# docling-serve — deploy config for the upstream docling-serve project
# ---------------------------------------------------------------------------

build-docling-serve: | $(TARGET_DIR)/docling-serve
	if command -v $(HELM) >/dev/null 2>&1; then \
		echo "[docling-serve] helm lint"; \
		$(HELM) lint docling-serve/helm; \
		echo "[docling-serve] rendering chart to target/"; \
		$(HELM) template docling-serve docling-serve/helm > "$(TARGET_DIR)/docling-serve/rendered.yaml"; \
	else \
		echo "[docling-serve] skipped — 'helm' not found"; \
	fi

test-docling-serve:
	@echo "[docling-serve] no standalone test — see 'make test-docling-serve-examples'"

deploy-docling-serve:
	if command -v $(HELM) >/dev/null 2>&1 && command -v $(OC) >/dev/null 2>&1 && $(OC) whoami >/dev/null 2>&1; then \
		echo "[docling-serve] deploying to namespace $(NAMESPACE)"; \
		$(HELM) upgrade --install docling-serve docling-serve/helm -n "$(NAMESPACE)" --create-namespace; \
	else \
		echo "[docling-serve] skipped — need 'helm' and an active 'oc login' session"; \
	fi

# ---------------------------------------------------------------------------
# docling-serve-examples — client calls against a running docling-serve
# ---------------------------------------------------------------------------

build-docling-serve-examples: | $(VENV_PYTHON)
	@echo "[docling-serve-examples] installing requirements"
	$(PIP) -q -r docling-serve-examples/python/requirements.txt

test-docling-serve-examples: build-docling-serve-examples | $(TARGET_DIR)/docling-serve-examples
	url="$(DOCLING_SERVE_URL)"; \
	if [ -z "$$url" ] && command -v $(OC) >/dev/null 2>&1 && $(OC) whoami >/dev/null 2>&1; then \
		host=$$($(OC) get route docling-serve -n "$(NAMESPACE)" -o jsonpath='{.spec.host}' 2>/dev/null || true); \
		if [ -n "$$host" ]; then url="https://$$host"; fi; \
	fi; \
	if [ -z "$$url" ]; then \
		echo "[docling-serve-examples] skipped — set DOCLING_SERVE_URL, or 'make deploy-docling-serve' first"; \
	else \
		echo "[docling-serve-examples] testing against $$url"; \
		$(PYTHON) docling-serve-examples/python/convert_file_sync.py "$(SAMPLE_STRUCTURED)" "$$url" "$(TARGET_DIR)/docling-serve-examples"; \
		$(PYTHON) docling-serve-examples/python/convert_file_async.py "$(SAMPLE_SCANNED)" "$$url" "$(TARGET_DIR)/docling-serve-examples"; \
	fi

deploy-docling-serve-examples:
	@echo "[docling-serve-examples] not applicable — client scripts have no deployable artifact"

# ---------------------------------------------------------------------------
# batch-via-pipeline-example — Data Science Pipeline (KFP)
# ---------------------------------------------------------------------------

build-batch-via-pipeline-example: | $(TARGET_DIR)/batch-via-pipeline-example $(VENV_PYTHON)
	@echo "[batch-via-pipeline-example] installing requirements"
	$(PIP) -q -r batch-via-pipeline-example/requirements.txt
	@echo "[batch-via-pipeline-example] compiling pipeline"
	$(PYTHON) batch-via-pipeline-example/pipeline.py "$(TARGET_DIR)/batch-via-pipeline-example/docling-batch-pipeline.yaml"

test-batch-via-pipeline-example: build-batch-via-pipeline-example
	@echo "[batch-via-pipeline-example] validating compiled pipeline is well-formed YAML"
	$(PYTHON) -c "import yaml, sys; yaml.safe_load(open('$(TARGET_DIR)/batch-via-pipeline-example/docling-batch-pipeline.yaml')); print('OK')"

deploy-batch-via-pipeline-example: build-batch-via-pipeline-example
	if [ -n "$(PIPELINES_ENDPOINT)" ]; then \
		echo "[batch-via-pipeline-example] submitting run to $(PIPELINES_ENDPOINT)"; \
		$(PYTHON) -c "\
from kfp.client import Client; \
c = Client(host='$(PIPELINES_ENDPOINT)'); \
c.create_run_from_pipeline_package('$(TARGET_DIR)/batch-via-pipeline-example/docling-batch-pipeline.yaml', arguments={'input_bucket': 'docling-input', 'output_bucket': 'docling-output'})"; \
	else \
		echo "[batch-via-pipeline-example] skipped — set PIPELINES_ENDPOINT to submit a run"; \
	fi

# ---------------------------------------------------------------------------
# serverless-api-example — FastAPI + Docling SDK on Knative Serverless
# ---------------------------------------------------------------------------

build-serverless-api-example: | $(VENV_PYTHON)
	@echo "[serverless-api-example] installing requirements"
	$(PIP) -q -r serverless-api-example/requirements-dev.txt
	if command -v $(PODMAN) >/dev/null 2>&1; then \
		echo "[serverless-api-example] building container image"; \
		$(PODMAN) build -f serverless-api-example/Containerfile -t "$(REGISTRY)/serverless-api-example:$(IMAGE_TAG)" serverless-api-example; \
	else \
		echo "[serverless-api-example] skipped image build — 'podman' not found"; \
	fi

test-serverless-api-example: build-serverless-api-example | $(TARGET_DIR)/serverless-api-example
	@echo "[serverless-api-example] running unit + integration tests"
	@echo "[serverless-api-example] (integration tests self-skip if SERVICE_URL is unreachable)"
	PYTHONPATH="$(ROOT_DIR)/serverless-api-example/src" \
	TARGET_DIR="$(TARGET_DIR)/serverless-api-example" \
	$(PYTHON) -m pytest serverless-api-example/tests/ -v -o cache_dir="$(TARGET_DIR)/serverless-api-example/.pytest_cache"

deploy-serverless-api-example:
	if command -v $(HELM) >/dev/null 2>&1 && command -v $(OC) >/dev/null 2>&1 && $(OC) whoami >/dev/null 2>&1; then \
		echo "[serverless-api-example] deploying to namespace $(NAMESPACE)"; \
		$(HELM) upgrade --install serverless-api-example serverless-api-example/deploy/helm -n "$(NAMESPACE)" --create-namespace \
			--set image.repository="$(REGISTRY)/serverless-api-example" --set image.tag="$(IMAGE_TAG)"; \
	else \
		echo "[serverless-api-example] skipped — need 'helm' and an active 'oc login' session"; \
	fi

# ---------------------------------------------------------------------------
# event-driven-example — Knative Eventing function
# ---------------------------------------------------------------------------

build-event-driven-example: | $(VENV_PYTHON)
	@echo "[event-driven-example] installing requirements"
	$(PIP) -q -r event-driven-example/requirements-dev.txt
	if command -v $(PODMAN) >/dev/null 2>&1; then \
		echo "[event-driven-example] building container image"; \
		$(PODMAN) build -f event-driven-example/Containerfile -t "$(REGISTRY)/docling-event-driven-example:$(IMAGE_TAG)" event-driven-example; \
	else \
		echo "[event-driven-example] skipped image build — 'podman' not found"; \
	fi

test-event-driven-example: build-event-driven-example | $(TARGET_DIR)/event-driven-example
	@echo "[event-driven-example] running tests (integration test self-skips without CLUSTER_URL/OPENSHIFT_CLUSTER)"
	$(PYTHON) -m pytest event-driven-example/tests/ -v -o cache_dir="$(TARGET_DIR)/event-driven-example/.pytest_cache"

deploy-event-driven-example:
	if command -v $(HELM) >/dev/null 2>&1 && command -v $(OC) >/dev/null 2>&1 && $(OC) whoami >/dev/null 2>&1; then \
		echo "[event-driven-example] deploying to namespace $(NAMESPACE)"; \
		$(HELM) upgrade --install docling-eventing event-driven-example/deploy/helm -n "$(NAMESPACE)" --create-namespace \
			--set image.repository="$(REGISTRY)/docling-event-driven-example" --set image.tag="$(IMAGE_TAG)"; \
	else \
		echo "[event-driven-example] skipped — need 'helm' and an active 'oc login' session"; \
	fi

# ---------------------------------------------------------------------------
# rag-via-ogx-example — Docling chunking + OpenShift AI Llama Stack (OGX)
# ---------------------------------------------------------------------------

build-rag-via-ogx-example: | $(VENV_PYTHON)
	@echo "[rag-via-ogx-example] installing requirements"
	$(PIP) -q -r rag-via-ogx-example/requirements.txt

test-rag-via-ogx-example: build-rag-via-ogx-example | $(TARGET_DIR)/rag-via-ogx-example
	if [ -n "$(LLAMA_STACK_URL)" ]; then \
		echo "[rag-via-ogx-example] ingesting sample against $(LLAMA_STACK_URL)"; \
		$(PYTHON) rag-via-ogx-example/ingest.py "$(SAMPLE_HYBRID)" "$(LLAMA_STACK_URL)" docling-smoke-test; \
		$(PYTHON) rag-via-ogx-example/query.py "What is this document about?" "$(LLAMA_STACK_URL)" docling-smoke-test \
			| tee "$(TARGET_DIR)/rag-via-ogx-example/query-output.txt"; \
	else \
		echo "[rag-via-ogx-example] skipped — set LLAMA_STACK_URL to a live LlamaStackDistribution route"; \
	fi

deploy-rag-via-ogx-example:
	@echo "[rag-via-ogx-example] not applicable — deploy a LlamaStackDistribution via the LlamaStack Operator, this is a client"

# ---------------------------------------------------------------------------
# mcp-example — docling-mcp server
# ---------------------------------------------------------------------------

build-mcp-example: | $(VENV_PYTHON)
	@echo "[mcp-example] installing requirements"
	$(PIP) -q -r mcp-example/requirements.txt
	if command -v $(PODMAN) >/dev/null 2>&1; then \
		echo "[mcp-example] building container image"; \
		$(PODMAN) build -f mcp-example/Containerfile -t "$(REGISTRY)/docling-mcp-example:$(IMAGE_TAG)" mcp-example; \
	else \
		echo "[mcp-example] skipped image build — 'podman' not found"; \
	fi

test-mcp-example: build-mcp-example | $(TARGET_DIR)/mcp-example
	@echo "[mcp-example] smoke-checking the server CLI"
	"$(VENV_DIR)/bin/docling-mcp-server" --help > "$(TARGET_DIR)/mcp-example/help-output.txt"
	@echo "OK — see $(TARGET_DIR)/mcp-example/help-output.txt"

deploy-mcp-example:
	if command -v $(OC) >/dev/null 2>&1 && $(OC) whoami >/dev/null 2>&1; then \
		echo "[mcp-example] deploying to namespace $(NAMESPACE)"; \
		$(OC) apply -f mcp-example/deploy/manifest.yaml -n "$(NAMESPACE)"; \
	else \
		echo "[mcp-example] skipped — need an active 'oc login' session"; \
	fi
