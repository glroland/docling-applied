#!/bin/bash
# Asynchronous file conversion: submit, poll for completion, fetch the
# result. Use this for large files or when you don't want to hold an open
# HTTP connection for the full conversion time.
#
# Usage: ./convert_file_async.sh <file> [docling-serve-url]
set -euo pipefail

INPUT_FILE="${1:?Usage: $0 <file> [docling-serve-url]}"
URL="${2:-}"
POLL_INTERVAL=5

if [ -z "$URL" ]; then
  NAMESPACE="${NAMESPACE:-docling}"
  DEPLOYMENT="${DEPLOYMENT:-docling-serve}"
  HOST=$(oc get route "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
  URL="https://$HOST"
fi

SUBMIT_RESPONSE=$(curl -s -X POST \
  "$URL/v1/convert/file/async" \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F "files=@$INPUT_FILE" \
  -F 'to_formats=md' \
  -F 'do_ocr=true' \
  -F 'image_export_mode=placeholder' \
  -F 'table_mode=fast' \
  -F 'abort_on_error=false')

TASK_ID=$(echo "$SUBMIT_RESPONSE" | jq -r '.task_id')

if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
  echo "Error: failed to get task_id from submission response" >&2
  echo "$SUBMIT_RESPONSE" >&2
  exit 1
fi

echo "Task submitted: $TASK_ID" >&2

while true; do
  POLL_RESPONSE=$(curl -s "$URL/v1/status/poll/$TASK_ID")
  TASK_STATUS=$(echo "$POLL_RESPONSE" | jq -r '.task_status')

  echo "Status: $TASK_STATUS" >&2

  if [ "$TASK_STATUS" = "success" ]; then
    break
  elif [ "$TASK_STATUS" = "failure" ]; then
    echo "Error: conversion failed" >&2
    echo "$POLL_RESPONSE" >&2
    exit 1
  fi

  sleep "$POLL_INTERVAL"
done

curl -s "$URL/v1/result/$TASK_ID" | jq -r .document.md_content
