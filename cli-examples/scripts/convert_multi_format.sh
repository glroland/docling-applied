#!/bin/bash
# Convert a document to several formats in one pass by repeating --to.
#
# Usage: ./convert_multi_format.sh <file> [output_dir]
set -euo pipefail

INPUT="${1:?Usage: $0 <file> [output_dir]}"
OUTPUT_DIR="${2:-output}"

mkdir -p "$OUTPUT_DIR"
docling --to md --to json --to text --output "$OUTPUT_DIR" "$INPUT"
