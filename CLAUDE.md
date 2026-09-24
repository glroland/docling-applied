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

Four of the nine — `serverless-api-example`, `event-driven-example`,
`rag-via-ogx-example`, and `mcp-example` — live under
`pending-redhat-testing/` rather than the repo root: complete
quickstarts, but not yet tested/confirmed against a real Red Hat
OpenShift AI 3.5 cluster. Preserve that grouping when editing them
(paths are `pending-redhat-testing/<example>/...`); move an example back
to the repo root only when told it's been verified.

`README.md` is the fast-path entry point (one-line-per-example table,
split into a main list and the pending-testing list above).
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
Also `REGISTRY`/`IMAGE_TAG` for image builds. These can go in a `.env`
file at the repo root (copy `.env.example`) instead of the command line —
the Makefile does `-include $(ROOT_DIR)/.env` before the `?=` defaults
that set them, so `.env` overrides the defaults and command-line values
still override `.env`. `.env` is gitignored; `.env.example` is not — keep
it in sync when adding a new overridable variable.

Fine-grained test targets: each archetype's `test-<example>` has no
recipe of its own, it chains `test-<example>-<piece>` targets (e.g.
`test-simple-examples-structured`) — run one of those directly to skip
the slow pieces (real OCR) during iteration. `make help` lists them all.

Example names: `simple-examples`, `cli-examples`, `docling-serve`,
`docling-serve-examples`, `batch-via-pipeline-example`,
`serverless-api-example`, `event-driven-example`, `rag-via-ogx-example`,
`mcp-example`.

### Per-example commands

- **`pending-redhat-testing/serverless-api-example/`** and
  **`pending-redhat-testing/event-driven-example/`** each have their own
  `Makefile` (`make install`, `make run`, `make test`, `make lint`,
  `make build`, `make push`) — it `-include`s the repo-root `.env` (two
  levels up) so `REGISTRY`/`IMAGE_TAG`/`PODMAN` still match the root
  Makefile's build-* targets for the same example. Single test:
  `PYTHONPATH=src pytest tests/src/test_convert_to_md.py::test_name -v`
  (from inside `pending-redhat-testing/serverless-api-example/`).
- **`docling-serve/`**: mostly deploys the upstream project's public
  image (`helm lint docling-serve/helm`, `helm template ...`, or
  `oc apply -f docling-serve/manifests/docling-serve-quickstart.yaml`)
  but also has its own `Containerfile` + `requirements.txt` for building
  a custom image on Red Hat's base image. That `requirements.txt`
  deliberately has no PyPI fallback (unlike the repo-root one) — see the
  comment in the file and `docling-serve/README.md` before changing it;
  adding PyPI back in previously produced a `docling`/`docling-jobkit`
  version mismatch that crashed the server at startup.
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

`make install`/`build-*` create one shared venv at a **fixed path,
`./venv` at the repo root** — deliberately not under `target/`, and not
conditional on shell state (an earlier version deferred to `$VIRTUAL_ENV`
when set; that made the effective venv path depend on which shell
invoked `make`, which was confusing and meant `make clean` could
silently take out whichever venv a target-less shell had fallen back to
— don't reintroduce that). It's pinned to Python 3.12
(`DOCLING_PYTHON_VERSION` in the Makefile) — matching the ABI Red Hat's
index publishes wheels for. When `uv` is on `PATH` it auto-provisions
that interpreter (`uv venv --python 3.12`); without uv, `python3 -m venv`
is used with a warning if the system interpreter isn't 3.12. `PIP`/`PYTHON`
Make variables always point into this venv — never call bare
`pip`/`python3` in a Makefile recipe. `make clean` never removes `./venv`
(reinstalling it means redownloading Docling/torch) — `make clean-venv`
does that explicitly.

### The "everything under target/" convention

No example script or Makefile recipe writes output or caches inside an
example's own folder — everything goes under `target/<example-name>/` at
the repo root (`make clean` removes it in one shot). This is enforced
throughout: scripts take an explicit output-directory argument rather
than defaulting to a local `output/` inside the repo, `PYTHONPYCACHEPREFIX`
is exported globally in the Makefile to redirect bytecode caches, and
pytest invocations pass `-o cache_dir=target/<example>/.pytest_cache`.
Preserve this when adding new scripts or Makefile targets. The one
deliberate exception is `./venv` (see above) — it's a repo-root sibling
of `target/`, not inside it, specifically so `make clean` doesn't remove
it.

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
  `batch-via-pipeline-example/`,
  `pending-redhat-testing/serverless-api-example/`, and
  `pending-redhat-testing/event-driven-example/` originated as working
  code from past customer engagements, since generalized (vendor-neutral
  object storage instead of Azure-specific, public base images instead
  of private ones, APIs re-verified against current Docling/docling-serve
  source).
- `cli-examples/`, `pending-redhat-testing/rag-via-ogx-example/`, and
  `pending-redhat-testing/mcp-example/` were built fresh against the
  upstream `docling`/`docling-mcp`/Llama Stack projects.
  `rag-via-ogx-example/`'s Llama Stack client API surface is the least
  stable dependency in this repo (see that example's README/docs for the
  native-API-vs-OpenAI-compatible-layer caveat) — verify method names
  against the target cluster's `llama-stack-client` version before
  relying on it.

None of this repo's manifests/images/resource sizing are meant to be
deployed as-is in a customer engagement — they're reference points to
adapt, not production configs.
