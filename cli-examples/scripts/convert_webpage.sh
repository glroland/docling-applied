#!/bin/bash
# Convert a live web page to Markdown — the `docling` CLI accepts a URL
# as the source directly, the same as a local file path.
#
# Usage: ./convert_webpage.sh <url> [output_dir]
set -euo pipefail

URL="${1:?Usage: $0 <url> [output_dir]}"
OUTPUT_DIR="${2:-output}"

mkdir -p "$OUTPUT_DIR"
docling --to md --output "$OUTPUT_DIR" "$URL"
