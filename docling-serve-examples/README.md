# docling-serve-examples

Client examples for the `docling-serve` REST API deployed by
[`../docling-serve/`](../docling-serve/). No SDK, no cluster access needed
beyond the API route — this is what a developer integrating with your
deployed Docling service actually writes.

## What's here

| File | Demonstrates |
|---|---|
| `curl/convert_file_sync.sh` | Upload a file, block until conversion finishes |
| `curl/convert_file_async.sh` | Submit, poll `task_status`, fetch the result |
| `curl/convert_webpage.sh` | Convert a URL via `/v1/convert/source` (no upload) |
| `python/convert_file_sync.py` | Same as above, as a `requests`-based client |
| `python/convert_file_async.py` | Same as above |
| `python/convert_webpage.py` | Same as above |

## Usage

```bash
# curl
NAMESPACE=docling DEPLOYMENT=docling-serve ./curl/convert_file_sync.sh ../samples/hybrid.pdf
./curl/convert_webpage.sh https://docling-project.github.io/docling/ https://<route-host>

# python
pip install -r python/requirements.txt
python python/convert_file_sync.py ../samples/hybrid.pdf https://<route-host> output/
python python/convert_file_async.py ../samples/scanned.pdf https://<route-host> output/
```

Each script accepts the docling-serve base URL as an argument; the curl
scripts fall back to resolving it from an OpenShift Route
(`NAMESPACE`/`DEPLOYMENT` env vars, default `docling`/`docling-serve`) when
none is given.

## Sync vs. async

Use sync (`/v1/convert/file`, `/v1/convert/source`) for small/interactive
conversions — the request blocks until Docling is done. Use async
(`/v1/convert/file/async` + `/v1/status/poll/{task_id}` +
`/v1/result/{task_id}`) for large documents or batch-style calls where you
don't want to hold a connection open; `docling-serve` also supports a
WebSocket status channel (`/v1/status/ws/{task_id}`) if you'd rather push
than poll.

## Response shape

Both sync and async results wrap the converted document as:

```json
{
  "document": {
    "md_content": "...",
    "json_content": { "...": "DoclingDocument" },
    "html_content": null,
    "text_content": null
  },
  "status": "success"
}
```

Only the formats you asked for in `to_formats` are populated — the others
stay `null`.
