# Documentation

Documentation for every Docling consumption pattern in this repo, aimed
at developers and architects evaluating how to bring Docling document
conversion into an application on Red Hat OpenShift AI 3.5.

Each approach below has its own doc covering what it is, how it works,
prerequisites, usage, and when (not) to reach for it.

## Approaches

| Doc | Example folder(s) | Pattern |
|---|---|---|
| [Simple Examples](simple-examples.md) | `simple-examples/` | Docling SDK called directly in Python — no service |
| [CLI Examples](cli-examples.md) | `cli-examples/` | The `docling` command-line tool — no Python |
| [Docling Serve](docling-serve.md) | `docling-serve/`, `docling-serve-examples/` | Deploy the upstream `docling-serve` REST API |
| [Batch via Pipeline](batch-via-pipeline-example.md) | `batch-via-pipeline-example/` | Data Science Pipeline (Kubeflow Pipelines) |

### Pending Red Hat testing

These four have not yet been tested/confirmed against a real Red Hat
OpenShift AI 3.5 cluster and live under
[`pending-redhat-testing/`](../pending-redhat-testing/) rather than the
repo root until that verification happens — see the note in the root
[`README.md`](../README.md#pending-red-hat-testing).

| Doc | Example folder(s) | Pattern |
|---|---|---|
| [Serverless API](serverless-api-example.md) | `pending-redhat-testing/serverless-api-example/` | Custom FastAPI service on Knative Serverless |
| [Event-Driven](event-driven-example.md) | `pending-redhat-testing/event-driven-example/` | Knative Eventing, triggered by object storage uploads |
| [RAG via OGX](rag-via-ogx-example.md) | `pending-redhat-testing/rag-via-ogx-example/` | Docling chunking + OpenShift AI's Llama Stack (OGX) |
| [MCP](mcp-example.md) | `pending-redhat-testing/mcp-example/` | `docling-mcp` — Docling as agent tools (Model Context Protocol) |

## Recommended approaches

If you're not sure where to start, start here:

- **[Simple Examples](simple-examples.md)** — the fastest way to learn what
  Docling actually does. No service, no cluster infrastructure, just the
  Python SDK in a notebook or script. This is where the mental model for
  every other approach in this repo comes from: `DocumentConverter` in,
  Markdown/JSON out, optionally chunked for RAG.
- **[Docling Serve](docling-serve.md)** — the default choice once you need
  Docling running as a service on your cluster. It's the officially
  supported, zero-custom-code path (the same shape Red Hat OpenShift AI
  ships internally), so it should be your first stop before reaching for
  a custom-built service.

Everything else in this repo is a more specific architecture — batch
processing, event-driven ingestion, a custom API, RAG, or agentic tool
use — that builds on the concepts these two establish. See each doc's
"When to use this" section for guidance on picking between them.

## Shared conventions

- **Sample data**: every example converts the same three PDFs in
  `../samples/` — `structured.pdf` (born-digital), `scanned.pdf`
  (image-only, exercises OCR), and `hybrid.pdf` (mixed).
- **Docling version**: pinned centrally in `../requirements.txt`, sourced
  from Red Hat's OpenShift AI 3.5 package index. Every example's own
  `requirements.txt` pulls this in rather than pinning its own version.
- **Smoke testing**: the root `../Makefile` orchestrates
  `install`/`build`/`test`/`deploy`/`clean` across every example — run
  `make help` from the repo root. All temp/output files land under
  `../target/`, never inside an example's own folder.
