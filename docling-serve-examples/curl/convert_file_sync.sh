#!/bin/bash
# Synchronous file conversion against a running docling-serve deployment.
# Blocks until the conversion finishes and prints the Markdown.
#
# Usage: ./convert_file_sync.sh <file> [docling-serve-url]
set -euo pipefail

INPUT_FILE="${1:?Usage: $0 <file> [docling-serve-url]}"
URL="${2:-}"

if [ -z "$URL" ]; then
  NAMESPACE="${NAMESPACE:-docling}"
  DEPLOYMENT="${DEPLOYMENT:-docling-serve}"
  HOST=$(oc get route "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
  URL="https://$HOST"
fi

curl -s -X POST \
  "$URL/v1/convert/file" \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F "files=@$INPUT_FILE" \
  -F 'to_formats=md' \
  -F 'do_ocr=true' \
  -F 'image_export_mode=placeholder' \
  -F 'table_mode=fast' \
  -F 'abort_on_error=false' \
  | jq -r .document.md_content
