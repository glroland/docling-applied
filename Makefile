# Orchestrates smoke testing across every example in this repo.
#
# Conventions:
#   - All temp/output files land under target/ (this Makefile creates
#     target/<example-name>/ per example). Nothing is ever written inside
#     an example's own subfolder.
#   - `make clean` removes target/ and nothing else. The shared venv
#     lives at ./venv, a fixed path outside target/, precisely so `make
#     clean` doesn't take it out — reinstalling it means redownloading
#     Docling/torch. `make clean-venv` removes it explicitly.
#   - Test data always comes from samples/ at the repo root.
#   - Steps that need a live cluster or external service (deploy targets,
#     and a few test targets) check for the required tool/endpoint first
#     and print a clear "skipped" message instead of failing the whole
#     run when it's not available — useful for running this against
#     whatever subset of infrastructure you actually have up.
#   - Each archetype's test-<name> target has no recipe of its own — it
#     just chains finer-grained test-<name>-<piece> targets (see
#     FINE_TESTS below), so a single slow piece (usually real OCR) can be
#     re-run alone instead of the whole archetype. `make test` is slow
#     because it's the full chain of all of them; run a fine-grained
#     target directly to iterate faster.
#   - Environment-specific values (REGISTRY, NAMESPACE, cluster URLs) can
#     go in an optional .env file at the repo root instead of being
#     passed on every command line — copy .env.example to .env. It's
#     gitignored and silently skipped if absent; command-line values
#     always override it.
#
# Usage:
#   make help
#   make build            # prepare/compile/package everything that has a build step
#   make test             # smoke-test everything (uses samples/, writes to target/) — slow
#   make test-simple-examples-structured   # one fast piece of one archetype — fast
#   make deploy            # deploy everything that has a deployable artifact
#   make clean             # rm -rf target/ (leaves ./venv alone)
#   make clean-venv        # rm -rf ./venv (only if you actually want to reinstall)
#   make test-docling-serve-examples DOCLING_SERVE_URL=https://...
#   cp .env.example .env && $EDITOR .env   # then just `make deploy`, no flags needed
#
# Run `make help` for the full list of per-example and fine-grained targets.

# Every recipe with multiple shell statements uses explicit backslash
# line-continuation (one logical recipe line per Make rule) rather than
# .ONESHELL, since .ONESHELL requires GNU Make >= 3.82 and macOS still
# ships 3.81 by default.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT_DIR    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TARGET_DIR  := $(ROOT_DIR)/target
SAMPLES_DIR := $(ROOT_DIR)/samples

# Optional environment-specific overrides (registry, namespace, cluster
# URLs, ...) — copy .env.example to .env and fill it in. Gitignored, so
# it's safe to put real values (not secrets — this is Make variables, not
# a secrets store) in there. `-include` means it's silently skipped if
# absent. Values from .env override the `?=` defaults below but are still
# overridable on the command line (`make deploy REGISTRY=...` always
# wins) — see `make help`.
-include $(ROOT_DIR)/.env

# Route all Python bytecode caches under target/, regardless of which
# example's scripts are running, so no __pycache__/ ever lands in a
# subfolder.
export PYTHONPYCACHEPREFIX := $(TARGET_DIR)/pycache

PODMAN ?= podman
HELM   ?= helm
OC     ?= oc

# Every example installs into one shared virtual environment at a fixed
# path: ./venv at the repo root — always the same path regardless of
# which shell invokes `make` or whether a venv happens to be active in
# it (an earlier version of this Makefile deferred to $VIRTUAL_ENV when
# set, which made the effective venv location depend on shell state —
# confusing, and it meant `make clean` could take out whichever venv
# target-less shells fell back to). `uv venv --python 3.12 venv` (see
# README Setup) creates the exact same path `make install` would anyway,
# so doing it yourself first vs. letting `make install` do it are
# equivalent, not different modes.
#
# Deliberately NOT under target/: rebuilding this venv means
# reinstalling Docling/torch from scratch, so `make clean` (which people
# run often, just to clear conversion output) must never touch it. Use
# `make clean-venv` to remove it explicitly.
#
# It should be pinned to the Python version Red Hat's RHOAI 3.5 package
# index publishes wheels for (see requirements.txt) — using a different
# Python is how you'd end up needing pip/uv to fall back off that index
# for docling itself, not just its platform-specific deps.
DOCLING_PYTHON_VERSION ?= 3.12
VENV_DIR    := $(ROOT_DIR)/venv
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

# Fine-grained test targets, one per slow/independent piece of each
# archetype's test — see the "Fine-grained test targets" section of
# `make help` output. The test-<example> targets above chain these
# rather than containing their own recipe.
FINE_TESTS := test-simple-examples-structured test-simple-examples-scanned test-simple-examples-chunking \
              test-cli-examples-convert-all test-cli-examples-ocr test-cli-examples-chunking \
              test-docling-serve-examples-sync test-docling-serve-examples-async \
              test-serverless-api-example-health test-serverless-api-example-convert-md \
              test-serverless-api-example-convert-json test-serverless-api-example-integration \
              test-event-driven-example-ingest test-event-driven-example-invalid-payload \
              test-rag-via-ogx-example-ingest test-rag-via-ogx-example-query

.PHONY: help clean clean-venv install build test deploy \
        $(addprefix build-,$(EXAMPLES)) \
        $(addprefix test-,$(EXAMPLES)) \
        $(addprefix deploy-,$(EXAMPLES)) \
        $(FINE_TESTS)

help:
	@echo "docling-applied — smoke test orchestration"
	@echo ""
	@echo "  make install   Install the central Docling pin (requirements.txt)"
	@echo "  make build     Prepare/compile every example that has a build step"
	@echo "  make test      Run every example's smoke test (writes to target/)"
	@echo "  make deploy    Deploy every example that has a deployable artifact"
	@echo "  make clean     Remove target/ (conversion output/caches — leaves ./venv alone)"
	@echo "  make clean-venv  Remove ./venv (only if you actually want to reinstall)"
	@echo ""
	@echo "Per-example targets: build-<name> / test-<name> / deploy-<name>, for:"
	@echo "  $(EXAMPLES)"
	@echo ""
	@echo "test-<name> is slow because it chains every fine-grained test for"
	@echo "that archetype. Run one directly to skip the rest, e.g. during"
	@echo "iteration (fast ones first, slow OCR/chunking ones last):"
	@echo "  $(FINE_TESTS)"
	@echo ""
	@echo "Environment-specific overrides (registry, namespace, cluster URLs):"
	@echo "  REGISTRY=$(REGISTRY)  IMAGE_TAG=$(IMAGE_TAG)  NAMESPACE=$(NAMESPACE)"
	@echo "  DOCLING_SERVE_URL=$(DOCLING_SERVE_URL)  LLAMA_STACK_URL=$(LLAMA_STACK_URL)  PIPELINES_ENDPOINT=$(PIPELINES_ENDPOINT)"
	@echo "  Set these via 'make deploy REGISTRY=...' on the command line, or"
	@echo "  once in a .env file at the repo root (copy .env.example) —"
	@echo "  command-line values always win over .env. Live-infra ones above"
	@echo "  are skipped cleanly, not failed, when unset/unreachable."
	@echo ""
	@echo "Uses 'uv pip' automatically when uv is on PATH, otherwise plain pip."

clean:
	rm -rf "$(TARGET_DIR)"
	@echo "Removed $(TARGET_DIR)"

clean-venv:
	rm -rf "$(VENV_DIR)"
	@echo "Removed $(VENV_DIR)"

# Creates the shared venv at the fixed ./venv path that every install/run
# target below depends on. Idempotent — skips creation if it already
# exists (whether make created it last time or you did yourself).
$(VENV_PYTHON):
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

# Chained from the fine-grained targets below rather than one recipe, so
# a single slow (OCR) piece can be re-run alone during iteration instead
# of the whole archetype every time.
test-simple-examples: test-simple-examples-structured test-simple-examples-scanned test-simple-examples-chunking

test-simple-examples-structured: build-simple-examples | $(TARGET_DIR)/simple-examples
	@echo "[simple-examples] converting structured.pdf (fast — no OCR)"
	$(PYTHON) simple-examples/scripts/convert_pdf.py "$(SAMPLE_STRUCTURED)" "$(TARGET_DIR)/simple-examples"

test-simple-examples-scanned: build-simple-examples | $(TARGET_DIR)/simple-examples
	@echo "[simple-examples] converting scanned.pdf (slow — runs OCR)"
	$(PYTHON) simple-examples/scripts/convert_pdf.py "$(SAMPLE_SCANNED)" "$(TARGET_DIR)/simple-examples"

test-simple-examples-chunking: build-simple-examples | $(TARGET_DIR)/simple-examples
	@echo "[simple-examples] chunking hybrid.pdf (slow — runs OCR)"
	$(PYTHON) simple-examples/scripts/chunking.py "$(SAMPLE_HYBRID)" "$(TARGET_DIR)/simple-examples"

deploy-simple-examples:
	@echo "[simple-examples] not applicable — SDK scripts have no deployable artifact"

# ---------------------------------------------------------------------------
# cli-examples — the `docling` command-line tool, no Python required
# ---------------------------------------------------------------------------

build-cli-examples: | $(VENV_PYTHON)
	@echo "[cli-examples] installing requirements (docling, for the CLI it ships)"
	$(PIP) -q -r cli-examples/requirements.txt

test-cli-examples: test-cli-examples-convert-all test-cli-examples-ocr test-cli-examples-chunking

# The comprehensive one: every sample PDF, converted to Markdown *and*
# JSON every time, via convert_multi_format.sh (md+json+text in one
# `docling` call per file) rather than separate md-only/json-only passes
# — doing both formats together is faster than parsing the same file
# twice. -ocr/-chunking below intentionally stay single-file (it's fine
# for those to cover less ground; this target is the one that always
# covers every sample).
test-cli-examples-convert-all: build-cli-examples | $(TARGET_DIR)/cli-examples
	@echo "[cli-examples] converting every sample to Markdown + JSON (one docling call per file)"
	for f in "$(SAMPLES_DIR)"/*.pdf; do \
		echo "  -> $$(basename "$$f")"; \
		PATH="$(VENV_DIR)/bin:$$PATH" bash cli-examples/scripts/convert_multi_format.sh "$$f" "$(TARGET_DIR)/cli-examples"; \
	done

test-cli-examples-ocr: build-cli-examples | $(TARGET_DIR)/cli-examples
	@echo "[cli-examples] converting scanned.pdf with forced OCR (slow)"
	PATH="$(VENV_DIR)/bin:$$PATH" bash cli-examples/scripts/convert_scanned_with_ocr.sh "$(SAMPLE_SCANNED)" "$(TARGET_DIR)/cli-examples"

test-cli-examples-chunking: build-cli-examples | $(TARGET_DIR)/cli-examples
	@echo "[cli-examples] chunking hybrid.pdf (slow — runs OCR)"
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

test-docling-serve-examples: test-docling-serve-examples-sync test-docling-serve-examples-async

# Both sub-targets resolve DOCLING_SERVE_URL the same way (explicit env
# var, else auto-discover the Route if `oc` is logged in) — duplicated
# rather than factored out so each stays a single self-contained recipe.
test-docling-serve-examples-sync: build-docling-serve-examples | $(TARGET_DIR)/docling-serve-examples
	url="$(DOCLING_SERVE_URL)"; \
	if [ -z "$$url" ] && command -v $(OC) >/dev/null 2>&1 && $(OC) whoami >/dev/null 2>&1; then \
		host=$$($(OC) get route docling-serve -n "$(NAMESPACE)" -o jsonpath='{.spec.host}' 2>/dev/null || true); \
		if [ -n "$$host" ]; then url="https://$$host"; fi; \
	fi; \
	if [ -z "$$url" ]; then \
		echo "[docling-serve-examples] skipped — set DOCLING_SERVE_URL, or 'make deploy-docling-serve' first"; \
	else \
		echo "[docling-serve-examples] sync convert against $$url"; \
		$(PYTHON) docling-serve-examples/python/convert_file_sync.py "$(SAMPLE_STRUCTURED)" "$$url" "$(TARGET_DIR)/docling-serve-examples"; \
	fi

test-docling-serve-examples-async: build-docling-serve-examples | $(TARGET_DIR)/docling-serve-examples
	url="$(DOCLING_SERVE_URL)"; \
	if [ -z "$$url" ] && command -v $(OC) >/dev/null 2>&1 && $(OC) whoami >/dev/null 2>&1; then \
		host=$$($(OC) get route docling-serve -n "$(NAMESPACE)" -o jsonpath='{.spec.host}' 2>/dev/null || true); \
		if [ -n "$$host" ]; then url="https://$$host"; fi; \
	fi; \
	if [ -z "$$url" ]; then \
		echo "[docling-serve-examples] skipped — set DOCLING_SERVE_URL, or 'make deploy-docling-serve' first"; \
	else \
		echo "[docling-serve-examples] async convert against $$url"; \
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

test-serverless-api-example: test-serverless-api-example-health test-serverless-api-example-convert-md test-serverless-api-example-convert-json test-serverless-api-example-integration

# health/convert-md/convert-json are unit tests (mocked converter, no
# Docling install needed, fast). integration hits a real running service
# and self-skips if SERVICE_URL is unreachable — still worth running by
# default since the skip is cheap, but it's the one worth isolating when
# you *do* have a service up and want to re-run just that.
test-serverless-api-example-health: build-serverless-api-example | $(TARGET_DIR)/serverless-api-example
	PYTHONPATH="$(ROOT_DIR)/serverless-api-example/src" \
	$(PYTHON) -m pytest serverless-api-example/tests/src/test_health.py -v -o cache_dir="$(TARGET_DIR)/serverless-api-example/.pytest_cache"

test-serverless-api-example-convert-md: build-serverless-api-example | $(TARGET_DIR)/serverless-api-example
	PYTHONPATH="$(ROOT_DIR)/serverless-api-example/src" \
	$(PYTHON) -m pytest serverless-api-example/tests/src/test_convert_to_md.py -v -o cache_dir="$(TARGET_DIR)/serverless-api-example/.pytest_cache"

test-serverless-api-example-convert-json: build-serverless-api-example | $(TARGET_DIR)/serverless-api-example
	PYTHONPATH="$(ROOT_DIR)/serverless-api-example/src" \
	$(PYTHON) -m pytest serverless-api-example/tests/src/test_convert_to_json.py -v -o cache_dir="$(TARGET_DIR)/serverless-api-example/.pytest_cache"

test-serverless-api-example-integration: build-serverless-api-example | $(TARGET_DIR)/serverless-api-example
	@echo "[serverless-api-example] integration test (self-skips if SERVICE_URL is unreachable)"
	PYTHONPATH="$(ROOT_DIR)/serverless-api-example/src" \
	TARGET_DIR="$(TARGET_DIR)/serverless-api-example" \
	$(PYTHON) -m pytest serverless-api-example/tests/src/test_integration_samples.py -v -o cache_dir="$(TARGET_DIR)/serverless-api-example/.pytest_cache"

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

test-event-driven-example: test-event-driven-example-ingest test-event-driven-example-invalid-payload

# Both self-skip without CLUSTER_URL/OPENSHIFT_CLUSTER set (see
# tests/test_send_cloud_event.py) — split so either can be re-run alone
# against a live deployment without the other.
test-event-driven-example-ingest: build-event-driven-example | $(TARGET_DIR)/event-driven-example
	$(PYTHON) -m pytest "event-driven-example/tests/test_send_cloud_event.py::TestSendCloudEvent::test_send_document_ingest_event" \
		-v -o cache_dir="$(TARGET_DIR)/event-driven-example/.pytest_cache"

test-event-driven-example-invalid-payload: build-event-driven-example | $(TARGET_DIR)/event-driven-example
	$(PYTHON) -m pytest "event-driven-example/tests/test_send_cloud_event.py::TestSendCloudEvent::test_send_invalid_payload_returns_400" \
		-v -o cache_dir="$(TARGET_DIR)/event-driven-example/.pytest_cache"

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

test-rag-via-ogx-example: test-rag-via-ogx-example-ingest test-rag-via-ogx-example-query

test-rag-via-ogx-example-ingest: build-rag-via-ogx-example | $(TARGET_DIR)/rag-via-ogx-example
	if [ -n "$(LLAMA_STACK_URL)" ]; then \
		echo "[rag-via-ogx-example] ingesting sample against $(LLAMA_STACK_URL)"; \
		$(PYTHON) rag-via-ogx-example/ingest.py "$(SAMPLE_HYBRID)" "$(LLAMA_STACK_URL)" docling-smoke-test; \
	else \
		echo "[rag-via-ogx-example] skipped — set LLAMA_STACK_URL to a live LlamaStackDistribution route"; \
	fi

# Depends on -ingest since a query needs data already ingested into the
# same vector_db_id.
test-rag-via-ogx-example-query: test-rag-via-ogx-example-ingest | $(TARGET_DIR)/rag-via-ogx-example
	if [ -n "$(LLAMA_STACK_URL)" ]; then \
		echo "[rag-via-ogx-example] querying against $(LLAMA_STACK_URL)"; \
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
