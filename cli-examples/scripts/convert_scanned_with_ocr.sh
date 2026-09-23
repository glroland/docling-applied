#!/bin/bash
# Convert a scanned (image-only) document, forcing a specific OCR engine.
# Useful when the default OCR engine picks the wrong result, or when you
# want to explicitly control which engine runs (rapidocr here).
#
# Usage: ./convert_scanned_with_ocr.sh <file> [output_dir]
set -euo pipefail

INPUT="${1:?Usage: $0 <file> [output_dir]}"
OUTPUT_DIR="${2:-output}"

mkdir -p "$OUTPUT_DIR"
docling --to md --ocr --ocr-engine rapidocr --image-export-mode placeholder --output "$OUTPUT_DIR" "$INPUT"
