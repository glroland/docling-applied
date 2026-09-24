# docling-serve

Deployment configs for the upstream [`docling-serve`](https://github.com/docling-project/docling-serve)
project on OpenShift — no custom code. This is the officially supported,
zero-code way to run Docling as an on-demand REST API, and the same shape
that Red Hat OpenShift AI ships internally (`docling-serve-cuda-ubi9`).

For client examples that call this API (curl, Python, sync and async), see
[`../docling-serve-examples/`](../docling-serve-examples/).

## What's here

- `manifests/docling-serve-quickstart.yaml` — a single `oc apply -f`, no
  Helm required. CPU image, one replica, Route included. Adapted from
  [docling-serve's own reference manifest](https://github.com/docling-project/docling-serve/blob/main/docs/deploy-examples/docling-serve-simple.yaml).
- `helm/` — a Helm chart for anything beyond a quick demo: configurable
  replicas, resources, GPU toggle, and Route/TLS settings.
- `Containerfile` + `requirements.txt` — build your own image instead of
  using the public one, on Red Hat's own base image. See
  [Building your own image](#building-your-own-image) below.

## Quickstart (plain manifest)

```bash
oc new-project docling
oc apply -f manifests/docling-serve-quickstart.yaml
oc get route docling-serve
```

Open `https://<route-host>/ui` for the built-in Gradio playground, or
`https://<route-host>/docs` for the OpenAPI docs.

## Helm chart

```bash
helm install docling-serve ./helm -n docling --create-namespace
```

Common overrides:

```bash
# Enable GPU acceleration (pin the CUDA image tag first — see the comment
# in values.yaml, CUDA images don't publish a `latest` tag)
helm install docling-serve ./helm -n docling \
  --set gpu.enabled=true \
  --set gpu.image.tag=v1.8.0

# Point the Helm release at a mirrored/internal registry (disconnected
# clusters, or Red Hat's own docling-serve-cuda-ubi9 image once available
# in your environment)
helm install docling-serve ./helm -n docling \
  --set image.repository=<your-registry>/docling-serve-cpu \
  --set image.tag=<your-tag>
```

See `helm/values.yaml` for the full set of options (resources, route
timeout, TLS termination, node selectors/tolerations).

## Building your own image

Instead of the public `ghcr.io/docling-project` image, you can build your
own on Red Hat OpenShift AI 3.5's own base image, with `docling-serve[rapidocr]`
installed from Red Hat's package index:

```bash
podman login registry.redhat.io   # requires a Red Hat subscription/entitlement
podman build -f Containerfile -t <your-registry>/docling-serve:<tag> .
podman push <your-registry>/docling-serve:<tag>

helm install docling-serve ./helm -n docling --create-namespace \
  --set image.repository=<your-registry>/docling-serve \
  --set image.tag=<tag>
```

Via the root Makefile: `make build-docling-serve` (builds it if `podman`
is available; needs `REGISTRY`/`IMAGE_TAG` set, e.g. via `.env`).

**Important — don't add a PyPI fallback to `requirements.txt` here.**
This file deliberately uses `--index-url` only (Red Hat's package index),
no `--extra-index-url`. Adding PyPI back in and resolving with a
looser/"best available" strategy pulls a newer `docling` off PyPI than
the `docling-jobkit` version it gets paired with from Red Hat's index —
confirmed by hitting exactly that: the server started but failed
application startup with `RuntimeError: Unexpected PDF backend type
PdfBackend.THREADED_DOCLING_PARSE`. Resolving from Red Hat's index alone
(the image builds on Linux/RHEL9, which that index has full native
coverage for) gives a self-consistent set instead. This is different
from the repo-root `requirements.txt`, which legitimately needs the PyPI
fallback for local dev on non-Linux machines.

## Notes

- **Port**: docling-serve listens on `5001` by default; that's what the
  Service/Route target.
- **Health checks**: the app exposes dedicated `/livez` and `/readyz`
  routes for Kubernetes probes (separate from the human-facing `/health`
  and `/version` endpoints).
- **Model caching**: the image downloads its layout/OCR models on first
  use. For disconnected/air-gapped clusters, pre-bake or pre-populate a PVC
  with the model cache — see
  [docling-serve's model-cache examples](https://github.com/docling-project/docling-serve/tree/main/docs/deploy-examples)
  (`docling-model-cache-job.yaml`, `docling-model-cache-pvc.yaml`) and point
  `config.artifactsPath` at the mount.
- **Scaling beyond one replica**: docling-serve's async task queue is
  in-memory per-pod by default. If you need multiple replicas with a shared
  queue, see docling-serve's Redis Queue (RQ) worker deployment example
  (`docling-serve-rq-workers.yaml` in the same upstream repo) rather than
  just bumping `replicaCount` here.
