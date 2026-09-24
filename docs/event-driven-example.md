# Event-Driven

**Folder:** [`pending-redhat-testing/event-driven-example/`](../pending-redhat-testing/event-driven-example/) · **Pattern:** Knative Eventing, triggered by object storage uploads · **Status:** pending Red Hat testing — not yet verified against a real cluster

## Overview

Convert documents automatically when they land in object storage, using
Knative Eventing. A CloudEvent describing where the new file is (bucket +
key) triggers a Knative Service, which downloads the file, converts it
with Docling, uploads the Markdown/JSON output, and emits a completion
event other services can subscribe to. Use this when conversion should be
a *reaction* to an upload rather than something a client explicitly
requests.

## How it works

```
Broker --(Trigger, type=com.docling.document.ingest)--> docling-process (Knative Service)
                                                              |
                                                       download from S3
                                                       convert with Docling
                                                       upload .md/.json to S3
                                                              |
                                                              v
                                            docling-process-output (Channel) --> your subscribers
```

If your source event comes from S3/ODF bucket notifications, front this
with a small adapter (or your storage provider's native
Knative/eventing integration) that translates the bucket-notification
payload into the CloudEvent shape below.

## Prerequisites

- OpenShift Serverless (Knative Serving **and** Eventing) with a
  `default` Broker in the target namespace
- An S3-compatible bucket (MinIO, ODF/Noobaa, or AWS S3) for input/output
- Python 3.11+, `podman`
- `podman login registry.redhat.io` with a valid Red Hat subscription —
  the Containerfile's base image (`registry.redhat.io/rhai/base-image-cpu-rhel9`)
  is on Red Hat's entitled registry

## Repository layout

| Path | Purpose |
|---|---|
| `src/func.py` | The event handler: parse CloudEvent → download → `DocumentConverter` → upload → publish completion event |
| `tests/test_send_cloud_event.py` | Sends a real CloudEvent to a deployed instance |
| `Containerfile`, `Makefile` | Build/deploy locally |
| `deploy/helm/` | Knative `Service`, `Trigger`, `InMemoryChannel`, S3 credentials `Secret` |

## Usage

Event payload:

```json
{
  "input":  { "bucket": "docling-input", "key": "documents/report.pdf" },
  "output": { "bucket": "docling-output", "key": "processed/report/" }
}
```

CloudEvent `type`: `com.docling.document.ingest`. On success, the
function publishes `com.docling.document.processed` (same references,
`"status": "success"`) to the output Channel.

```bash
cd pending-redhat-testing/event-driven-example
make build IMAGE=quay.io/<your-org>/docling-event-driven-example:0.1.0
make push  IMAGE=quay.io/<your-org>/docling-event-driven-example:0.1.0
make deploy IMAGE=quay.io/<your-org>/docling-event-driven-example:0.1.0 NAMESPACE=docling
```

Or via Helm directly:

```bash
helm upgrade --install docling-eventing deploy/helm -n docling --create-namespace \
  --set image.repository=quay.io/<your-org>/docling-event-driven-example \
  --set image.tag=0.1.0 \
  --set s3.endpoint=https://s3.example.com \
  --set s3.accessKeyId=... \
  --set s3.secretAccessKey=...
```

Via the root Makefile: `make build-event-driven-example`,
`make test-event-driven-example`, `make deploy-event-driven-example`.

## Configuration reference

| Setting | Where | Notes |
|---|---|---|
| `OUTPUT_CHANNEL_URL` | env / Helm | Where completion events are published; defaults to the chart's own Channel |
| `AWS_S3_ENDPOINT`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `docling-s3-storage` Secret | S3 credentials, `boto3`-compatible |
| Trigger filter | `type: com.docling.document.ingest` | Only ingest events reach the function |
| Output Channel | `InMemoryChannel` by default | Swap for a durable channel (e.g. Kafka) beyond demo use — events don't survive a pod restart otherwise |

## When to use this

- Conversion should happen automatically on upload, not on request.
- A landing-zone bucket feeding a downstream ingestion or RAG pipeline.

**Not** for: on-demand conversion in response to a client call — see
[Docling Serve](docling-serve.md) or
[Serverless API](serverless-api-example.md). Not for processing an
existing large corpus in bulk — see
[Batch via Pipeline](batch-via-pipeline-example.md).
