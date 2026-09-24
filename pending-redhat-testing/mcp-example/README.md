# mcp-example

Expose Docling as tools for AI agents via the Model Context Protocol,
using the upstream [`docling-mcp`](https://github.com/docling-project/docling-mcp)
server. This is the pattern for "let an agent call Docling itself"
(convert a document, generate one, or run agentic RAG) rather than a
human/application calling a REST API directly.

## Modes

`docling-mcp` runs in one of three modes, controlled by
`DOCLING_MCP_CONVERSION_MODE`:

- **`local`** — converts documents in-process (`pip install docling-mcp[local]`).
  Simple, no other infrastructure, but every client pays Docling's model
  load cost.
- **`remote`** (recommended) — delegates conversion to a `docling-serve`
  deployment via HTTP. Point it at [`../../docling-serve/`](../../docling-serve/)
  from this repo.
- **`hybrid`** — remote with automatic local fallback
  (`DOCLING_MCP_FALLBACK_TO_LOCAL=true`).

## Desktop client (stdio)

For Claude Desktop, LM Studio, or any MCP client that spawns a local
process: copy one of `client-config/claude_desktop_local.json` or
`client-config/claude_desktop_remote.json` into your client's MCP server
config (for Claude Desktop, `claude_desktop_config.json`), filling in
`DOCLING_MCP_SERVICE_URL` with your `docling-serve` route for the remote
variant.

```bash
# quick manual test, either mode
uvx --from docling-mcp docling-mcp-server --transport stdio
```

## Network-reachable server (streamable-http)

For agent frameworks that need an MCP endpoint over HTTP rather than a
local process — including Llama Stack, which speaks `sse` — build and
deploy `docling-mcp` as a service on OpenShift, in remote mode against
`docling-serve`. The Containerfile's base image is on Red Hat's entitled
registry — run `podman login registry.redhat.io` (requires a Red Hat
subscription) before building.

```bash
podman build -f Containerfile -t quay.io/<your-org>/docling-mcp-example:0.1.0 .
podman push quay.io/<your-org>/docling-mcp-example:0.1.0

oc apply -f deploy/manifest.yaml
oc set env deployment/docling-mcp DOCLING_MCP_SERVICE_URL=https://<docling-serve-route>
oc get route docling-mcp
```

For Llama Stack integration specifically, launch with
`--transport sse` instead (see the Containerfile's `CMD` for where to
change it) and register the resulting URL as a tool group in your
`LlamaStackDistribution`.

## Toolgroups

`docling-mcp-server` takes a list of toolgroups as trailing positional
arguments; the default is `conversion generation manipulation`. Add
`llama-index-rag` or `llama-stack-rag` to enable agentic RAG tools that
embed/query a vector database directly from the agent conversation (see
`docling_mcp`'s own README for the full config surface — `DOCLING_MCP_LLS_*`
/ `DOCLING_MCP_LI_*` env vars). Compare against
[`../rag-via-ogx-example/`](../rag-via-ogx-example/), which does the same
retrieval by explicit code instead of agent tool calls — useful for seeing
what the agent is actually doing under the hood.

## Example prompts

See `prompts/example-prompts.md`.

## Notes

- `docling-mcp`'s tool surface (which tools exist, exact argument names)
  is still evolving quickly — check `docling-mcp-server --help` and the
  package's own README/CHANGELOG against the version you install before
  building on it for a customer engagement.
- The MCP Python SDK made a breaking v1→v2 jump; `docling-mcp>=3.0.0`
  requires `mcp>=2.0.0`. If your client hasn't migrated, pin
  `docling-mcp<3.0.0`.
