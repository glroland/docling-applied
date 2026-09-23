# docling-applied

Quickstarts for using [Docling](https://github.com/docling-project/docling)
on Red Hat OpenShift AI 3.5 — converting PDFs, images, and web pages to
Markdown and JSON, and building on that conversion (batch processing,
event-driven ingestion, RAG, agentic tool use).

Each example is a self-contained, incrementally more involved way to
consume Docling. Start at the top and go as deep as the problem you're
solving actually needs.

| Example | Pattern | When to reach for it |
|---|---|---|
| [`simple-examples/`](simple-examples/) | Docling SDK, called directly | Learning what Docling does; a notebook/workbench workflow with no service |
| [`cli-examples/`](cli-examples/) | The `docling` command-line tool | One-off conversions or shell-pipeline use, no Python |
| [`docling-serve/`](docling-serve/) + [`docling-serve-examples/`](docling-serve-examples/) | Deploy the upstream `docling-serve` REST API | The default choice for "I need a Docling API on my cluster" — no custom code |
| [`batch-via-pipeline-example/`](batch-via-pipeline-example/) | Data Science Pipeline (KFP) | Converting a whole bucket of documents at once; scheduled/repeatable ingestion |
| [`serverless-api-example/`](serverless-api-example/) | Custom FastAPI service on Knative Serverless | You need business logic docling-serve doesn't provide (custom auth, response shaping, embedding Docling in a larger API) |
| [`event-driven-example/`](event-driven-example/) | Knative Eventing, CloudEvents | Conversion should react to an upload landing in object storage, not a client request |
| [`rag-via-ogx-example/`](rag-via-ogx-example/) | Docling chunking + OpenShift AI Llama Stack (OGX) | Full RAG: parse, chunk, embed, retrieve, generate |
| [`mcp-example/`](mcp-example/) | `docling-mcp` (Model Context Protocol) | An agent should call Docling itself, not a human/application |

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
