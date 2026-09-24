# serverless-api-example

A custom FastAPI microservice that wraps the Docling SDK directly and
deploys as a Knative Serverless workload (scale-to-zero, GPU-aware) on
OpenShift Serverless.

**Before reaching for this one**: if you just need a REST API in front of
Docling, deploy [`../../docling-serve/`](../../docling-serve/) instead — it's
the officially supported, zero-code path. Build this pattern when you need
something docling-serve doesn't give you out of the box: custom auth,
response shaping, per-tenant logic, embedding a Docling call inside a
larger existing API, or the scale-to-zero Knative cost profile specifically
(as opposed to a normal Deployment).

## What it does

- `POST /convert_to_md/` — upload a document, get Markdown streamed back
  one page at a time (chunked transfer encoding), images base64-embedded
  inline
- `POST /convert_to_json/` — upload a document, get the full Docling
  document JSON back in one response
- `GET /health` — liveness/readiness
- Supports PDF, DOCX, PPTX, XLSX, HTML, PNG, JPEG, TIFF
- RapidOCR for scanned content; CPU/CUDA/MPS accelerator selection
- Scale-to-zero via Knative Serving; GPU node selector when `gpu.enabled`

## Running locally

```bash
make install
make run          # http://localhost:8080 ($PORT to override)
make test         # unit tests (mock the converter, no Docling install needed)
```

Integration tests hit a real running instance:

```bash
make run &
pytest tests/src/test_integration_samples.py -v
```

## Building and deploying

The Containerfile's base image is on Red Hat's entitled registry — run
`podman login registry.redhat.io` (requires a Red Hat subscription) before
building.

```bash
make build REGISTRY=quay.io/<your-org> IMAGE_TAG=0.1.0
make push  REGISTRY=quay.io/<your-org> IMAGE_TAG=0.1.0

helm install serverless-api-example ./deploy/helm -n docling --create-namespace \
  --set image.repository=quay.io/<your-org>/serverless-api-example \
  --set image.tag=0.1.0
```

Requires OpenShift Serverless (Knative Serving) installed, and — if
`gpu.enabled=true` (the default) — GPU nodes with the NVIDIA GPU operator.
See `deploy/helm/values.yaml` for the full set of options (resources,
autoscaling, timeouts, GPU toggle). `deploy/argocd-app.yaml` is available
for GitOps-managed deployment.

## Architecture notes

- `src/app/services/converter.py` — the Docling SDK usage: a cached
  `DocumentConverter` (models load once, not per-request), RapidOCR,
  page-batch-size tuning, and streaming Markdown export with embedded
  images (`ImageRefMode.EMBEDDED`). This is the part worth reading if
  you're adapting this into your own service.
- Conversion runs in a thread-pool executor (`run_in_executor`) so
  Docling's blocking, CPU/GPU-bound work doesn't stall the async event
  loop.
- The container image is a public UBI Python base with `docling[rapidocr]`
  installed at build time — no pre-baked dependency. For faster cold
  starts (Docling downloads ~1GB of models on first use), layer your own
  image with the models pre-cached; see docling-serve's
  `docling-model-cache-job.yaml` pattern in
  [docling-serve's deploy-examples](https://github.com/docling-project/docling-serve/tree/main/docs/deploy-examples)
  for the idea, adapted to this image.
