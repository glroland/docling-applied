# rag-via-ogx-example

End-to-end RAG: Docling parses and chunks a document, and OpenShift AI's
**Llama Stack** distribution (OGX) embeds, stores, retrieves, and
generates the answer. This is the natural "what's next" after
`simple-examples/` — same Docling chunking step, now feeding a real
retrieval+generation stack instead of just printing chunks.

## Why split it this way

Docling's `HybridChunker` chunks on document structure (headings, tables,
sections) instead of a fixed token count, which tends to produce more
coherent retrieval units than generic text splitters. Llama Stack then
owns everything downstream of "here are the chunks": embedding model
selection, vector storage, retrieval, and LLM serving — all configured
once at the platform level instead of per-application.

## Prerequisites

- A `LlamaStackDistribution` deployed in your OpenShift AI project (via the
  LlamaStack Operator), with an inference model and an embedding model
  registered, and a vector database provider configured (inline Milvus,
  remote Milvus, FAISS, or pgvector — `ingest.py` defaults to a
  `provider_id` of `"milvus"`; change it to match your distribution)
- The Llama Stack route/URL for that distribution

## Usage

```bash
pip install -r requirements.txt

python ingest.py ../samples/hybrid.pdf https://<llama-stack-route> docling-rag-example
python query.py "What does this document say about X?" https://<llama-stack-route> docling-rag-example
```

`ingest.py`:
1. Converts and chunks the document with Docling
2. Picks the distribution's registered embedding model
   (`client.models.list()`, filtered to `model_type == "embedding"`)
3. Registers a vector database (`client.vector_dbs.register`)
4. Inserts the Docling chunks directly (`client.vector_io.insert`) —
   bypassing Llama Stack's own chunker, since Docling already did that job

`query.py`:
1. Retrieves the top-k relevant chunks (`client.vector_io.query`)
2. Builds a context-grounded prompt and calls the distribution's
   registered LLM (`client.inference.chat_completion`)

## A note on API stability

Llama Stack's client API is evolving quickly, and OpenShift AI's Llama
Stack distribution exposes more than one surface for RAG:

- The **native Llama Stack API** used here — `vector_dbs`, `vector_io`,
  `tool_runtime.rag_tool`, `inference.chat_completion` — is the
  longer-standing one and what this example is built against.
- A newer **OpenAI-compatible layer** (`client.files`, `client.vector_stores`,
  `client.responses` with a `file_search` tool) is also available on recent
  OpenShift AI versions, useful if you want to reuse existing
  OpenAI-SDK-based code against your Llama Stack deployment instead.

Before relying on this in a customer engagement, verify the exact method
names against the `llama-stack-client` version your target OpenShift AI
3.5 cluster ships (`pip show llama-stack-client`, and the distribution's
own `/docs` route) — a couple of minor-version bumps have changed method
signatures in this SDK.

## Alternative: Agents API

For a more "agentic" version of `query.py` — where Llama Stack's Agent
handles retrieval as a tool call instead of you calling `vector_io.query`
by hand — see the `builtin::rag` tool in Llama Stack's Agents API and
[Red Hat's Llama Stack application examples](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/working_with_llama_stack/llama-stack-adv-examples_rag)
for the current syntax on your version. Not included here to keep this
quickstart to the retrieval mechanics you'll actually reuse.
