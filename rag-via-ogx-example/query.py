#!/usr/bin/env python3
"""Retrieve relevant Docling chunks from Llama Stack's vector store and
generate an answer with the LLM it has configured.

Usage:
    python query.py "<question>" <llama-stack-base-url> [vector_db_id]

Run ingest.py against one or more documents first.
"""

import sys

from llama_stack_client import LlamaStackClient

TOP_K = 5


def _pick_llm_model(client: LlamaStackClient) -> str:
    models = client.models.list()
    return next(m.identifier for m in models if m.model_type == "llm").identifier


def ask(question: str, base_url: str, vector_db_id: str) -> None:
    client = LlamaStackClient(base_url=base_url)
    model_id = _pick_llm_model(client)

    retrieval = client.vector_io.query(
        vector_db_id=vector_db_id,
        query=question,
        params={"max_chunks": TOP_K},
    )
    chunks = retrieval.chunks
    print(f"Retrieved {len(chunks)} chunk(s) from '{vector_db_id}'\n")

    context = "\n\n---\n\n".join(chunk.content for chunk in chunks)
    prompt = (
        "Answer the question using only the context below. "
        "If the context doesn't contain the answer, say so.\n\n"
        f"Context:\n{context}\n\nQuestion: {question}"
    )

    response = client.inference.chat_completion(
        model_id=model_id,
        messages=[{"role": "user", "content": prompt}],
    )
    print("Answer:")
    print(response.completion_message.content)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(
            f'Usage: {sys.argv[0]} "<question>" <llama-stack-base-url> [vector_db_id]',
            file=sys.stderr,
        )
        sys.exit(1)

    question = sys.argv[1]
    base_url = sys.argv[2].rstrip("/")
    vector_db_id = sys.argv[3] if len(sys.argv) > 3 else "docling-rag-example"
    ask(question, base_url, vector_db_id)
