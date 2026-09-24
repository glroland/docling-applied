# Serverless API

**Folder:** [`pending-redhat-testing/serverless-api-example/`](../pending-redhat-testing/serverless-api-example/) · **Pattern:** Custom FastAPI service on Knative Serverless · **Status:** pending Red Hat testing — not yet verified against a real cluster

## Overview

A custom FastAPI microservice that wraps the Docling SDK directly and
deploys as a Knative Serverless workload (scale-to-zero, GPU-aware) on
OpenShift Serverless. Build this when you need something
[Docling Serve](docling-serve.md) doesn't give you out of the box: custom
auth, response shaping, per-tenant logic, embedding a Docling call inside
a larger existing API, or the scale-to-zero Knative cost profile
specifically (as opposed to a normal Deployment or KServe
`InferenceService`).

## How it works

```
POST /convert_to_md/?filename=... ──► write upload to temp file
                                              │
                                              ▼
                                   converter.stream_to_markdown()
                                     (DocumentConverter, cached,
                                      runs in a thread-pool executor)
                                              │
                                              ▼
                          StreamingResponse — one Markdown chunk per page,
                                images base64-embedded inline

POST /convert_to_json/?filename=... ──► converter.convert_to_json() ──► full DoclingDocument JSON
```

The `DocumentConverter` is initialized once and cached
(`@lru_cache`, keyed on `page_batch_size`) — expensive model loading
happens on first use, not per-request. Conversion runs in a thread-pool
executor so Docling's blocking, CPU/GPU-bound work doesn't stall the
async event loop.

## Prerequisites

- Python 3.11+, `podman` (or another OCI builder)
- `podman login registry.redhat.io` with a valid Red Hat subscription —
  the Containerfile's base image (`registry.redhat.io/rhai/base-image-cpu-rhel9`)
  is on Red Hat's entitled registry
- OpenShift Serverless (Knative Serving) installed
- GPU nodes with the NVIDIA GPU operator, only if `gpu.enabled=true`
  (the Helm chart default)

## Repository layout

| Path | Purpose |
|---|---|
| `src/app/main.py` | FastAPI app entry point |
| `src/app/config.py` | Settings (device, log level, max upload size, ...) via `pydantic-settings` |
| `src/app/routers/{health,convert_to_md,convert_to_json}.py` | The three endpoints |
| `src/app/services/converter.py` | The Docling SDK usage — cached converter, RapidOCR, streaming Markdown export |
| `tests/` | Unit tests (mocked converter) + integration tests (real running service, self-skip if unreachable) |
| `Containerfile`, `Makefile` | Build/run/test locally |
| `deploy/helm/` | Knative `Service`, GPU toggle, autoscaling config |
| `deploy/argocd-app.yaml` | GitOps deployment |

## Usage

```bash
cd pending-redhat-testing/serverless-api-example
make install
make run          # http://localhost:8080
make test         # unit tests; integration tests self-skip if nothing's running

make build REGISTRY=quay.io/<your-org> IMAGE_TAG=0.1.0
make push  REGISTRY=quay.io/<your-org> IMAGE_TAG=0.1.0

helm install serverless-api-example ./deploy/helm -n docling --create-namespace \
  --set image.repository=quay.io/<your-org>/serverless-api-example \
  --set image.tag=0.1.0
```

Via the root Makefile: `make build-serverless-api-example`,
`make test-serverless-api-example`,
`make deploy-serverless-api-example`.

## Configuration reference

| Endpoint | Method | Notes |
|---|---|---|
| `/health` | `GET` | Liveness/readiness |
| `/convert_to_md/?filename=...&page_batch_size=10` | `POST` | Raw binary body; streamed Markdown, one chunk per page, images base64-embedded |
| `/convert_to_json/?filename=...&page_batch_size=10` | `POST` | Raw binary body; full Docling JSON in one response |

| Env var (`src/app/config.py`) | Default | Purpose |
|---|---|---|
| `DEVICE` | `cpu` | `cpu`, `cuda`, or `mps` |
| `MAX_FILE_SIZE_MB` | `50` | Upload size limit |
| `LOG_LEVEL` | `INFO` | |
| `DOCLING_ARTIFACTS_PATH` | `/opt/app-root/src/.cache/docling/models` | Cached model path |

Supported extensions: `.pdf` `.docx` `.pptx` `.xlsx` `.html` `.png`
`.jpeg` `.tiff`.

## When to use this

- You need business logic Docling Serve doesn't provide: custom auth,
  response shaping, embedding conversion inside a larger API.
- You specifically want Knative's scale-to-zero cost profile for a
  general-purpose (non-model-serving) GPU workload.

**Not** for: the default "just give me a Docling API" case — deploy
[Docling Serve](docling-serve.md) instead, it's less to build and
maintain. Not for upload-triggered conversion — see
[Event-Driven](event-driven-example.md), which shares this example's
Docling-wrapping approach but reacts to storage events instead of HTTP
requests.
