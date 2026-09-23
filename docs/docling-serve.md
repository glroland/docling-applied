# Docling Serve

**Folders:** [`docling-serve/`](../docling-serve/) (deployment), [`docling-serve-examples/`](../docling-serve-examples/) (clients) · **Pattern:** Deploy the upstream `docling-serve` REST API · **Recommended default**

## Overview

Deployment configs for the upstream
[`docling-serve`](https://github.com/docling-project/docling-serve)
project — no custom code. This is the officially supported, zero-code way
to run Docling as an on-demand REST API on OpenShift, and the same shape
Red Hat OpenShift AI ships internally as the `docling-serve-cuda-ubi9`
container image. If you need "a Docling API on my cluster" and don't have
a reason to build something custom, start here.

## How it works

```
client ──HTTP──► docling-serve (Deployment/Route, port 5001)
                         │
                         ▼
                  DocumentConverter (same SDK as simple-examples/)
                         │
                         ▼
                  { "document": { "md_content": ..., "json_content": ... } }
```

`docling-serve` wraps the same `DocumentConverter` used everywhere else
in this repo behind a FastAPI service with sync and async endpoints, an
optional Gradio UI, and OpenAPI docs.

## Prerequisites

- An OpenShift cluster (or any Kubernetes cluster with Routes, for the
  Route-specific manifests)
- `oc` and either `helm` (for the Helm chart) or nothing extra (for the
  plain manifest)
- GPU nodes with the NVIDIA GPU operator, only if deploying the CUDA
  image variant

## Repository layout

**`docling-serve/`** (deployment):

| Path | Purpose |
|---|---|
| `manifests/docling-serve-quickstart.yaml` | Single `oc apply -f`, CPU image, no Helm |
| `helm/` | Helm chart: configurable replicas, resources, GPU toggle, Route/TLS |

**`docling-serve-examples/`** (clients):

| Path | Purpose |
|---|---|
| `curl/convert_file_sync.sh` | Upload a file, block until conversion finishes |
| `curl/convert_file_async.sh` | Submit, poll `task_status`, fetch the result |
| `curl/convert_webpage.sh` | Convert a URL via `/v1/convert/source` (no upload) |
| `python/convert_file_sync.py`, `convert_file_async.py`, `convert_webpage.py` | Same three, as `requests`-based Python clients |

## Usage

Deploy:

```bash
# Quickest path
oc new-project docling
oc apply -f docling-serve/manifests/docling-serve-quickstart.yaml
oc get route docling-serve

# Or, for GPU / configurable resources / TLS
helm install docling-serve docling-serve/helm -n docling --create-namespace
```

Call it:

```bash
NAMESPACE=docling DEPLOYMENT=docling-serve docling-serve-examples/curl/convert_file_sync.sh samples/hybrid.pdf
docling-serve-examples/curl/convert_webpage.sh https://docling-project.github.io/docling/ https://<route-host>

pip install -r docling-serve-examples/python/requirements.txt
python docling-serve-examples/python/convert_file_async.py samples/scanned.pdf https://<route-host> output/
```

Via the root Makefile: `make deploy-docling-serve` then
`make test-docling-serve-examples` (auto-discovers the Route if `oc` is
logged in, or set `DOCLING_SERVE_URL` explicitly).

## Configuration reference

| Setting | Where | Notes |
|---|---|---|
| Port | Fixed at `5001` | Service/Route both target this |
| Health checks | `/livez`, `/readyz` | Dedicated k8s-probe routes (separate from human-facing `/health`) |
| `DOCLING_SERVE_ENABLE_UI` | ConfigMap / env | Enables the Gradio playground at `/ui` |
| GPU | `helm --set gpu.enabled=true --set gpu.image.tag=<version>` | CUDA images don't publish a `latest` tag — pin explicitly |
| Sync endpoints | `POST /v1/convert/file`, `POST /v1/convert/source` | Block until conversion completes |
| Async endpoints | `POST /v1/convert/file/async` + `GET /v1/status/poll/{task_id}` + `GET /v1/result/{task_id}` | Also has a WebSocket status channel, `/v1/status/ws/{task_id}` |
| Response shape | `{"document": {"md_content", "json_content", ...}, "status": ...}` | Only the formats requested in `to_formats` are populated |
| Model caching | `docling-model-cache-job.yaml` / `-pvc.yaml` upstream | For disconnected/air-gapped clusters — see `docling-serve/README.md` |
| Scaling beyond 1 replica | Upstream `docling-serve-rq-workers.yaml` | Default async queue is in-memory per-pod |

## When to use this

- The default choice whenever you need Docling behind a REST API and
  don't need custom business logic in front of it.
- You want the same officially-supported shape OpenShift AI 3.5 ships
  internally, so your deployment story matches what Red Hat supports.

**Not** for: cases needing custom auth, response shaping, or Docling
embedded inside a larger existing API — see
[Serverless API](serverless-api-example.md) for that. Not for
upload-triggered (rather than request-driven) conversion — see
[Event-Driven](event-driven-example.md).
