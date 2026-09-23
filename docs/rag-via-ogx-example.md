# RAG via OGX

**Folder:** [`rag-via-ogx-example/`](../rag-via-ogx-example/) · **Pattern:** Docling chunking + OpenShift AI's Llama Stack (OGX)

## Overview

End-to-end RAG: Docling parses and chunks a document, and OpenShift AI's
**Llama Stack** distribution (OGX) embeds, stores, retrieves, and
generates the answer. This is the natural "what's next" after
[Simple Examples](simple-examples.md) — the same `HybridChunker` step,
now feeding a real retrieval-and-generation stack instead of just
printing chunks.

## How it works

```
ingest.py:
  Docling convert + HybridChunker  ──►  chunks
        │
        ▼
  client.vector_dbs.register(...)          # once per vector_db_id
        │
        ▼
  client.vector_io.insert(vector_db_id, chunks)   # Docling's chunks, as-is —
                                                   # bypasses Llama Stack's own chunker

query.py:
  client.vector_io.query(vector_db_id, query)  ──►  top-k chunks
        │
        ▼
  client.inference.chat_completion(model_id, [context-grounded prompt])  ──►  answer
```

Docling's `HybridChunker` chunks on document structure (headings,
sections, tables) instead of a fixed token count, producing more
coherent retrieval units than generic text splitters. Llama Stack owns
everything downstream: embedding model selection, vector storage,
retrieval, and LLM serving — configured once at the platform level.

## Prerequisites

- A `LlamaStackDistribution` deployed in your OpenShift AI project (via
  the LlamaStack Operator), with an inference model and an embedding
  model registered, and a vector database provider configured (inline
  Milvus, remote Milvus, FAISS, or pgvector)
- The Llama Stack route/URL for that distribution
- Python 3.11+, `pip install -r rag-via-ogx-example/requirements.txt`

## Repository layout

| Path | Purpose |
|---|---|
| `ingest.py` | Convert + chunk a document, register a vector DB, insert the chunks |
| `query.py` | Retrieve top-k chunks, generate a context-grounded answer |

## Usage

```bash
pip install -r rag-via-ogx-example/requirements.txt

python rag-via-ogx-example/ingest.py samples/hybrid.pdf https://<llama-stack-route> docling-rag-example
python rag-via-ogx-example/query.py "What does this document say about X?" https://<llama-stack-route> docling-rag-example
```

Via the root Makefile: `make test-rag-via-ogx-example LLAMA_STACK_URL=<route>`.

## Configuration reference

| Setting | Where | Notes |
|---|---|---|
| `provider_id` (vector DB) | `ingest.py`, hardcoded to `"milvus"` | Change to match your distribution (`faiss`, `pgvector`, ...) |
| Embedding model | Auto-selected | `client.models.list()`, filtered to `model_type == "embedding"` |
| LLM | Auto-selected | `client.models.list()`, filtered to `model_type == "llm"` |
| Top-k | `query.py`, `TOP_K = 5` | Number of chunks retrieved per query |

**API stability note**: this uses Llama Stack's native API
(`vector_dbs`, `vector_io`, `inference.chat_completion`). OpenShift AI's
Llama Stack distribution also exposes a newer OpenAI-compatible layer
(`client.files`, `client.vector_stores`, `client.responses` with a
`file_search` tool). Verify exact method names against the
`llama-stack-client` version your cluster ships before relying on this in
a customer engagement — this API surface moves quickly.

## When to use this

- You need real retrieval-augmented generation: embed, store, retrieve,
  generate — not just parse-and-chunk.
- Your target platform already runs OpenShift AI's Llama Stack
  distribution and you want to use its managed embedding/vector/inference
  stack rather than standing up your own.

**Not** for: cases without a Llama Stack distribution available — see
[Simple Examples](simple-examples.md)'s chunking step as the reusable
building block, paired with whatever vector store/LLM stack you do have.
Not for agent-driven retrieval — see [MCP](mcp-example.md)'s
`llama-stack-rag` toolgroup for that variant.
