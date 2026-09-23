# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Quickstart reference implementations for consuming
[Docling](https://github.com/docling-project/docling) (document → Markdown/JSON,
including OCR and chunking) on Red Hat OpenShift AI 3.5. This is not one
application — it's nine independent example folders, each demonstrating a
different consumption pattern (direct SDK use, CLI, REST API, batch
pipeline, custom microservice, event-driven, RAG, agentic/MCP), plus a
`docs/` reference layer and a root `Makefile` that smoke-tests all of them.

`README.md` is the fast-path entry point (one-line-per-example table).
`docs/README.md` is the full reference layer — read a `docs/<name>.md`
file before making non-trivial changes to the corresponding example, it
documents the intended architecture and config surface in more depth than
the example's own README.

## Commands

### Root-level orchestration (`Makefile` at repo root)

```bash
make help                          # list all targets
make install                       # install the central Docling pin only
make build / test / deploy         # run that verb across every example
make build-<example> / test-<example> / deploy-<example>   # single example
make clean                         # rm -rf target/ (the only place this Makefile writes)
```

Live-infrastructure overrides (targets skip cleanly, don't fail, when
unset/unreachable): `NAMESPACE`, `DOCLING_SERVE_URL`, `LLAMA_STACK_URL`,
`PIPELINES_ENDPOINT`, e.g. `make test-docling-serve-examples DOCLING_SERVE_URL=https://...`.

Example names: `simple-examples`, `cli-examples`, `docling-serve`,
`docling-serve-examples`, `batch-via-pipeline-example`,
`serverless-api-example`, `event-driven-example`, `rag-via-ogx-example`,
`mcp-example`.

### Per-example commands

- **`serverless-api-example/`** and **`event-driven-example/`** each have
  their own `Makefile` (`make install`, `make run`, `make test`,
  `make lint`, `make build`, `make push`). Single test:
  `PYTHONPATH=src pytest tests/src/test_convert_to_md.py::test_name -v`
  (from inside `serverless-api-example/`).
- **`docling-serve/`**: `helm lint docling-serve/helm`,
  `helm template ... docling-serve/helm`, or
  `oc apply -f docling-serve/manifests/docling-serve-quickstart.yaml`.
- **`batch-via-pipeline-example/`**: `python pipeline.py [output.yaml]`
  compiles the KFP pipeline (output path is an optional CLI arg, not
  hardcoded — see below).
- Everything else is plain scripts: `python <script>.py <args>` or
  `bash <script>.sh <args>`.

## Architecture

### The central Docling version pin

`requirements.txt` at the repo root is the *only* place the Docling
version is pinned. Every example's own `requirements.txt` does
`-r ../requirements.txt` instead of pinning its own version — never add a
direct `docling[...]==` line to an example's requirements file.

The root file sets `--index-url` to Red Hat's RHOAI 3.5 package index
(`packages.redhat.com/.../cpu-ubi9/simple/`) and `--extra-index-url` to
PyPI. This ordering matters: Red Hat's index is primary so `docling`
itself is guaranteed to resolve from there, but that index only ships
**Linux wheels**, so PyPI is listed as a fallback for platform-specific
compiled deps (`pydantic-core`, `torch`, ...) on macOS/Windows dev
machines. `--index-strategy unsafe-best-match` is required to make that
fallback work with `uv` (uv's default "first index wins per package"
strategy would otherwise refuse to fall back) — it's uv-only, so it's
applied in the Makefile, not in `requirements.txt` itself (plain pip
doesn't understand that flag and doesn't need it).

### The shared venv and Python pinning

`make install`/`build-*` create one shared venv at `target/venv`, pinned
to Python 3.12 (`DOCLING_PYTHON_VERSION` in the Makefile) — matching the
ABI Red Hat's index publishes wheels for. When `uv` is on `PATH` it
auto-provisions that interpreter (`uv venv --python 3.12`); without uv,
`python3 -m venv` is used with a warning if the system interpreter isn't
3.12. `PIP`/`PYTHON` Make variables always point into this venv — never
call bare `pip`/`python3` in a Makefile recipe.

### The "everything under target/" convention

No example script or Makefile recipe writes output, caches, or venvs
inside an example's own folder — everything goes under `target/<example-name>/`
at the repo root (`make clean` removes it in one shot). This is enforced
throughout: scripts take an explicit output-directory argument rather
than defaulting to a local `output/` inside the repo, `PYTHONPYCACHEPREFIX`
is exported globally in the Makefile to redirect bytecode caches, and
pytest invocations pass `-o cache_dir=target/<example>/.pytest_cache`.
Preserve this when adding new scripts or Makefile targets.

### `samples/`

Shared test data used across examples. The original three files
(`structured.pdf` — born-digital, `scanned.pdf` — image-only/OCR,
`hybrid.pdf` — mixed) are what the Makefile and most example scripts
reference by name; additional numbered samples have since been added for
broader coverage. Always source test documents from here rather than
adding per-example copies.

### The nine patterns

Each is independent and self-contained (own README, own deps); `docs/`
has the fuller writeup for each including an architecture diagram.
Recommended entry points are `simple-examples/` (SDK, no infra) and
`docling-serve/` (the officially-supported REST deployment) — see
`docs/README.md`'s "Recommended approaches" section for the full
decision guidance before adding a new pattern or modifying an existing
one's scope.

Two provenance notes worth knowing before editing:
- `simple-examples/`, `docling-serve/`+`docling-serve-examples/`,
  `batch-via-pipeline-example/`, `serverless-api-example/`, and
  `event-driven-example/` originated as working code from past customer
  engagements, since generalized (vendor-neutral object storage instead
  of Azure-specific, public base images instead of private ones, APIs
  re-verified against current Docling/docling-serve source).
- `cli-examples/`, `rag-via-ogx-example/`, and `mcp-example/` were built
  fresh against the upstream `docling`/`docling-mcp`/Llama Stack projects.
  `rag-via-ogx-example/`'s Llama Stack client API surface is the least
  stable dependency in this repo (see that example's README/docs for the
  native-API-vs-OpenAI-compatible-layer caveat) — verify method names
  against the target cluster's `llama-stack-client` version before
  relying on it.

None of this repo's manifests/images/resource sizing are meant to be
deployed as-is in a customer engagement — they're reference points to
adapt, not production configs.
