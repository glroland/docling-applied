#!/usr/bin/env python3
"""Convert a document and split it into structure-aware chunks.

This is the step between "convert to Markdown/JSON" and "load into a vector
database": Docling's HybridChunker walks the document's structure (sections,
tables, lists) rather than cutting text at a fixed character count, so each
chunk stays semantically coherent. See
pending-redhat-testing/rag-via-ogx-example/ for how these chunks get
embedded and queried through Llama Stack.

Usage:
    python chunking.py <path/to/file.pdf> [output_dir]
"""

import json
import sys
from pathlib import Path

from docling.chunking import HybridChunker
from docling.document_converter import DocumentConverter


def convert_and_chunk(input_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    converter = DocumentConverter()
    result = converter.convert(str(input_path))

    chunker = HybridChunker()
    chunks = list(chunker.chunk(dl_doc=result.document))

    records = [
        {
            "index": i,
            "text": chunk.text,
            "headings": getattr(chunk.meta, "headings", None),
        }
        for i, chunk in enumerate(chunks)
    ]

    out_path = output_dir / f"{input_path.stem}.chunks.json"
    out_path.write_text(json.dumps(records, indent=2), encoding="utf-8")

    print(f"{len(chunks)} chunk(s) written to {out_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path/to/file.pdf> [output_dir]", file=sys.stderr)
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("output")
    convert_and_chunk(input_path, output_dir)
