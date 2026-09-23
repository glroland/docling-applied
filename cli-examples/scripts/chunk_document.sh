#!/bin/bash
# Convert and split a document into structure-aware chunks in one CLI
# call — the same HybridChunker used in simple-examples/, but without
# writing any Python. Useful as the parsing step feeding a shell-based
# or externally-orchestrated RAG ingestion pipeline.
#
# Usage: ./chunk_document.sh <file> [output_dir]
set -euo pipefail

INPUT="${1:?Usage: $0 <file> [output_dir]}"
OUTPUT_DIR="${2:-output}"

mkdir -p "$OUTPUT_DIR"
docling --to chunks --chunks-type hybrid --output "$OUTPUT_DIR" "$INPUT"
