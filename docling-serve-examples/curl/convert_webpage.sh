#!/bin/bash
# Convert a live web page by URL using the /v1/convert/source endpoint
# (no file upload — docling-serve fetches the page itself).
#
# Usage: ./convert_webpage.sh <page-url> [docling-serve-url]
set -euo pipefail

PAGE_URL="${1:?Usage: $0 <page-url> [docling-serve-url]}"
URL="${2:-}"

if [ -z "$URL" ]; then
  NAMESPACE="${NAMESPACE:-docling}"
  DEPLOYMENT="${DEPLOYMENT:-docling-serve}"
  HOST=$(oc get route "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
  URL="https://$HOST"
fi

curl -s -X POST \
  "$URL/v1/convert/source" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d "{
    \"options\": {\"to_formats\": [\"md\"]},
    \"sources\": [{\"kind\": \"http\", \"url\": \"$PAGE_URL\"}]
  }" \
  | jq -r .document.md_content
