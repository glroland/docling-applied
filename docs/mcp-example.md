# MCP

**Folder:** [`mcp-example/`](../mcp-example/) · **Pattern:** `docling-mcp` — Docling as agent tools (Model Context Protocol)

## Overview

Expose Docling as tools for AI agents via the Model Context Protocol,
using the upstream
[`docling-mcp`](https://github.com/docling-project/docling-mcp) server.
This is the pattern for "let an agent call Docling itself" (convert a
document, generate one, or run agentic RAG) rather than a
human/application calling a REST API directly.

## How it works

```
MCP client (Claude Desktop, LM Studio, Llama Stack agent, ...)
        │  stdio / sse / streamable-http
        ▼
  docling-mcp-server
        │
        ├── local mode   ──► converts documents in-process
        └── remote mode  ──► delegates to a docling-serve deployment (see docling-serve.md)
```

Three conversion modes, controlled by `DOCLING_MCP_CONVERSION_MODE`:
**local** (in-process, `docling-mcp[local]`), **remote** (delegates to
[Docling Serve](docling-serve.md) — recommended), and **hybrid** (remote
with automatic local fallback).

## Prerequisites

- Python 3.11+, `pip install docling-mcp` (or `docling-mcp[local]` for
  local mode)
- For remote mode: a running [Docling Serve](docling-serve.md) deployment
- For network-reachable (streamable-http) deployment: `podman`, `oc`, and
  `podman login registry.redhat.io` with a valid Red Hat subscription —
  the Containerfile's base image (`registry.redhat.io/rhai/base-image-cpu-rhel9`)
  is on Red Hat's entitled registry

## Repository layout

| Path | Purpose |
|---|---|
| `client-config/claude_desktop_local.json` | Desktop client config, local conversion mode |
| `client-config/claude_desktop_remote.json` | Desktop client config, remote mode against `docling-serve` |
| `Containerfile`, `deploy/manifest.yaml` | Run `docling-mcp` as a streamable-http service on OpenShift |
| `prompts/example-prompts.md` | Representative prompts: convert, generate, agentic RAG |

## Usage

Desktop client (stdio) — copy a config into your MCP client (e.g. Claude
Desktop's `claude_desktop_config.json`):

```bash
uvx --from docling-mcp docling-mcp-server --transport stdio
```

Network-reachable server (streamable-http), remote mode against
`docling-serve`:

```bash
podman build -f mcp-example/Containerfile -t quay.io/<your-org>/docling-mcp-example:0.1.0 mcp-example
podman push quay.io/<your-org>/docling-mcp-example:0.1.0

oc apply -f mcp-example/deploy/manifest.yaml
oc set env deployment/docling-mcp DOCLING_MCP_SERVICE_URL=https://<docling-serve-route>
```

Via the root Makefile: `make build-mcp-example`, `make test-mcp-example`
(smoke-checks the CLI), `make deploy-mcp-example`.

## Configuration reference

| Env var | Default | Purpose |
|---|---|---|
| `DOCLING_MCP_CONVERSION_MODE` | `remote` | `local`, `remote`, or (with `DOCLING_MCP_FALLBACK_TO_LOCAL=true`) hybrid |
| `DOCLING_MCP_SERVICE_URL` | — | Target `docling-serve` instance, for remote mode |
| `DOCLING_MCP_SERVICE_API_KEY` | — | API key for the service, if required |

Toolgroups (trailing positional args to `docling-mcp-server`, default
`conversion generation manipulation`): add `llama-index-rag` or
`llama-stack-rag` for agentic RAG tools that embed/query a vector
database directly from the agent conversation — see
`docling_mcp`'s own README for the `DOCLING_MCP_LLS_*`/`DOCLING_MCP_LI_*`
config surface. Compare against
[RAG via OGX](rag-via-ogx-example.md), which does the same retrieval by
explicit code instead of agent tool calls.

Transports: `stdio` (Claude Desktop, LM Studio), `sse` (Llama Stack),
`streamable-http` (containerized deployments).

**Stability note**: `docling-mcp`'s tool surface is still evolving
quickly, and its MCP SDK made a breaking v1→v2 jump (`docling-mcp>=3.0.0`
requires `mcp>=2.0.0`; pin `docling-mcp<3.0.0` for older clients). Check
`docling-mcp-server --help` against the version you install.

## When to use this

- An AI agent (not a human or a fixed application) needs to decide when
  and how to call Docling — convert a document, generate one, or run
  retrieval as part of a larger agentic workflow.

**Not** for: a fixed, predictable conversion call from application code —
use [Docling Serve](docling-serve.md) or
[Simple Examples](simple-examples.md) directly; going through an agent
adds latency and unpredictability you don't need for a deterministic
call.
