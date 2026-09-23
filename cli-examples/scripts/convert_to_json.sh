#!/bin/bash
# Convert a document to Docling JSON using the `docling` CLI directly.
#
# Usage: ./convert_to_json.sh <file> [output_dir]
set -euo pipefail

INPUT="${1:?Usage: $0 <file> [output_dir]}"
OUTPUT_DIR="${2:-output}"

mkdir -p "$OUTPUT_DIR"
docling --to json --output "$OUTPUT_DIR" "$INPUT"
