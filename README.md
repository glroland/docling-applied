# docling-applied

Quickstarts for using [Docling](https://github.com/docling-project/docling)
on Red Hat OpenShift AI 3.5 — converting PDFs, images, and web pages to
Markdown and JSON, and building on that conversion (batch processing,
event-driven ingestion, RAG, agentic tool use).

Each example is a self-contained, incrementally more involved way to
consume Docling. Start at the top and go as deep as the problem you're
solving actually needs.

**Full documentation for every approach — overview, architecture,
prerequisites, configuration reference, and when (not) to use it — lives
in [`docs/`](docs/). This README is the fast path; `docs/` is the
reference.**

| Example | Pattern | When to reach for it |
|---|---|---|
| [`simple-examples/`](simple-examples/) ([docs](docs/simple-examples.md)) | Docling SDK, called directly | Learning what Docling does; a notebook/workbench workflow with no service |
| [`cli-examples/`](cli-examples/) ([docs](docs/cli-examples.md)) | The `docling` command-line tool | One-off conversions or shell-pipeline use, no Python |
| [`docling-serve/`](docling-serve/) + [`docling-serve-examples/`](docling-serve-examples/) ([docs](docs/docling-serve.md)) | Deploy the upstream `docling-serve` REST API | The default choice for "I need a Docling API on my cluster" — no custom code |
| [`batch-via-pipeline-example/`](batch-via-pipeline-example/) ([docs](docs/batch-via-pipeline-example.md)) | Data Science Pipeline (KFP) | Converting a whole bucket of documents at once; scheduled/repeatable ingestion |
| [`serverless-api-example/`](serverless-api-example/) ([docs](docs/serverless-api-example.md)) | Custom FastAPI service on Knative Serverless | You need business logic docling-serve doesn't provide (custom auth, response shaping, embedding Docling in a larger API) |
| [`event-driven-example/`](event-driven-example/) ([docs](docs/event-driven-example.md)) | Knative Eventing, CloudEvents | Conversion should react to an upload landing in object storage, not a client request |
| [`rag-via-ogx-example/`](rag-via-ogx-example/) ([docs](docs/rag-via-ogx-example.md)) | Docling chunking + OpenShift AI Llama Stack (OGX) | Full RAG: parse, chunk, embed, retrieve, generate |
| [`mcp-example/`](mcp-example/) ([docs](docs/mcp-example.md)) | `docling-mcp` (Model Context Protocol) | An agent should call Docling itself, not a human/application |

## Setup

These instructions assume you're running on **Linux** (matching what the
examples themselves deploy to — OpenShift, containers, workbenches).
macOS/Windows local dev works too, but see the note at the end of this
section.

```bash
uv venv --python 3.12 venv
source venv/bin/activate
cp .env.example .env   # optional — fill in your registry/namespace/cluster URLs
make install
```

The venv always lives at `./venv` — a fixed path, not conditional on
shell state — whether you create it yourself first (as above) or skip
straight to `make install`, which creates it at that same path if it
doesn't exist yet. `make clean` never removes it (that would mean
redownloading Docling/torch on the next run); use `make clean-venv` if
you actually want to reinstall it. Either way, packages are resolved
from **`requirements.txt`**, which points at
**Red Hat's OpenShift AI 3.5 package index**
(`packages.redhat.com/.../rhoai/3.5/cpu-ubi9/`) as the primary source
rather than public PyPI. That index carries Red Hat's own patched,
security-scanned builds of Docling and its dependencies — the same
packages RHOAI 3.5 ships internally — so what you install locally matches
what actually runs on the platform, not just an arbitrary upstream
release. PyPI is listed as a fallback only for packages that index
doesn't carry for your platform (see `requirements.txt`'s comments).

`--python 3.12` matters: Red Hat's index only publishes wheels for that
Python version, so creating the venv with a different interpreter can
leave `uv`/`pip` unable to resolve compiled dependencies. On Linux this
is usually just a version match; on macOS/Windows, Red Hat's index is
Linux-wheel-only regardless of Python version, so `uv`/`unsafe-best-match`
falls back to PyPI for platform-specific packages there — Docling itself
still comes from Red Hat's index, but you won't get the fully
Red-Hat-sourced dependency chain outside Linux. See `requirements.txt`
and the root `Makefile`'s comments for the full mechanics.

### Environment-specific values (registry, namespace, cluster URLs)

Every `deploy-*` target and several `test-*` targets take values that are
specific to your cluster — which registry to push images to, which
namespace to deploy into, which route a live `docling-serve`/Llama Stack
instance is at. Rather than passing these on every command line, copy
`.env.example` to `.env` and fill it in; the Makefile loads it
automatically (`-include .env`, so it's silently skipped if you never
create one). `.env` is gitignored. Command-line values always win over
`.env`, which always wins over the Makefile's built-in defaults:

```bash
make deploy REGISTRY=quay.io/one-off-override   # wins even with a .env present
```

## Suggested path

1. **`simple-examples/`** — run the notebook, understand what
   `DocumentConverter` and `HybridChunker` actually do.
2. **`docling-serve/`** — deploy it, hit it from
   **`docling-serve-examples/`**. This is the API contract most of the
   other examples build on or assume.
3. Pick the shape that matches your use case: **batch** (pipeline),
   **request-driven with custom logic** (serverless), **upload-triggered**
   (event-driven), **RAG** (Llama Stack), or **agentic** (MCP).

## Shared assets

- `docs/` — full documentation for every approach; start at
  [`docs/README.md`](docs/README.md).
- `samples/` — three representative PDFs used across the examples:
  `structured.pdf` (born-digital, clean layout), `scanned.pdf`
  (image-only, exercises OCR), and `hybrid.pdf` (mixed).
- `requirements.txt` — the single source of truth for the Docling version
  used everywhere in this repo (`docling[rapidocr]`, pinned to the version
  RHOAI 3.5 itself ships, sourced from Red Hat's package index). Every
  example's own `requirements.txt` pulls this in via `-r ../requirements.txt`
  instead of pinning its own version. Run `make install` to install just
  this baseline, or `make build` to install it plus everything each
  example needs.
- `Makefile` — orchestrates `install`/`build`/`test`/`deploy`/`clean`
  across every example for smoke testing; run `make help`. Uses `uv pip`
  automatically when `uv` is on `PATH`. All temp/output files land under
  `target/` (never inside an example's own folder); `make clean` removes it.
- `.env.example` — template for environment-specific overrides (registry,
  namespace, cluster URLs); copy to `.env` and fill in — see
  [Setup](#setup).

## Provenance

`simple-examples/`, `docling-serve/`/`docling-serve-examples/`,
`batch-via-pipeline-example/`, `serverless-api-example/`, and
`event-driven-example/` were built from working code used in past
customer engagements, generalized (vendor-neutral storage, public base
images, corrected against Docling's current APIs) into standalone
quickstarts. `cli-examples/`, `rag-via-ogx-example/`, and `mcp-example/`
are new, built against the upstream `docling`/`docling-serve`/`docling-mcp`/
Llama Stack projects directly. None of this is meant to be taken as-is
into production —
verify image references, resource sizing, and API surfaces (especially
Llama Stack's, which is still moving quickly) against your actual
OpenShift AI 3.5 cluster before relying on any of it in a customer
engagement.
