#!/usr/bin/env python3
"""Parse and chunk a document with Docling, then embed and store the chunks
in a vector database managed by OpenShift AI's Llama Stack distribution.

Docling does the structure-aware parsing/chunking (HybridChunker); Llama
Stack does the embedding, storage, and later retrieval — this is the
division of labor Red Hat's own production-RAG reference architecture
uses (Docling for parse+chunk, Llama Stack/vLLM for embed+serve).

Usage:
    python ingest.py <path/to/file.pdf> <llama-stack-base-url> [vector_db_id]

See query.py to retrieve and generate an answer from what this ingests.
"""

import sys
from pathlib import Path

from docling.chunking import HybridChunker
from docling.document_converter import DocumentConverter
from llama_stack_client import LlamaStackClient


def _pick_embedding_model(client: LlamaStackClient):
    models = client.models.list()
    embedding_model = next(m for m in models if m.model_type == "embedding")
    dimension = int(embedding_model.metadata["embedding_dimension"])
    return embedding_model.identifier, dimension


def ingest(input_path: Path, base_url: str, vector_db_id: str) -> None:
    client = LlamaStackClient(base_url=base_url)

    embedding_model_id, embedding_dimension = _pick_embedding_model(client)
    print(f"Using embedding model: {embedding_model_id} (dim={embedding_dimension})")

    # Registering an already-registered vector_db_id is a no-op on most
    # providers; if yours errors instead, check first with
    # client.vector_dbs.list() and skip register() when it already exists.
    client.vector_dbs.register(
        vector_db_id=vector_db_id,
        embedding_model=embedding_model_id,
        embedding_dimension=embedding_dimension,
        provider_id="milvus",  # matches the LlamaStackDistribution's configured vector store
    )

    print(f"Converting {input_path} with Docling...")
    converter = DocumentConverter()
    result = converter.convert(str(input_path))

    chunker = HybridChunker()
    doc_chunks = list(chunker.chunk(dl_doc=result.document))
    print(f"{len(doc_chunks)} chunk(s) produced by HybridChunker")

    chunks = [
        {
            "content": chunk.text,
            "metadata": {
                "document_id": input_path.name,
                "chunk_index": i,
                "headings": getattr(chunk.meta, "headings", None),
            },
        }
        for i, chunk in enumerate(doc_chunks)
    ]

    client.vector_io.insert(vector_db_id=vector_db_id, chunks=chunks)
    print(f"Inserted {len(chunks)} chunk(s) into vector_db '{vector_db_id}'")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(
            f"Usage: {sys.argv[0]} <path/to/file.pdf> <llama-stack-base-url> [vector_db_id]",
            file=sys.stderr,
        )
        sys.exit(1)

    input_path = Path(sys.argv[1])
    base_url = sys.argv[2].rstrip("/")
    vector_db_id = sys.argv[3] if len(sys.argv) > 3 else "docling-rag-example"
    ingest(input_path, base_url, vector_db_id)
