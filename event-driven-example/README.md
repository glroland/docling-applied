# event-driven-example

Convert documents automatically when they land in object storage, using
Knative Eventing. A CloudEvent describing where the new file is (bucket +
key) triggers a Knative Service, which downloads the file, converts it
with Docling, uploads the Markdown/JSON output, and emits a completion
event other services can subscribe to.

Use this pattern when conversion should be a reaction to an upload rather
than something a client explicitly requests — e.g. a landing-zone bucket
that feeds a downstream ingestion or RAG pipeline. If your source event
comes from S3/ODF bucket notifications, you'd typically front this with a
small adapter (or your storage provider's native Knative/eventing
integration) that translates the bucket-notification payload into the
CloudEvent shape below and posts it to the Broker.

## Event payload

```json
{
  "input":  { "bucket": "docling-input", "key": "documents/report.pdf" },
  "output": { "bucket": "docling-output", "key": "processed/report/" }
}
```

CloudEvent `type`: `com.docling.document.ingest`. On success, the function
publishes a `com.docling.document.processed` event (same input/output
references plus `"status": "success"`) to the output Channel, so a
downstream Trigger can react to completed conversions.

## Architecture

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

## Running locally

```bash
pip install -r requirements-dev.txt
AWS_S3_ENDPOINT=http://localhost:9000 \
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
python src/func.py
```

Send it a test event:

```bash
CLUSTER_URL=http://localhost:8080 pytest tests/ -v
```

## Deploying

Requires OpenShift Serverless (Knative Serving + Eventing) with a
`default` Broker in the target namespace. The Containerfile's base image
is on Red Hat's entitled registry — run `podman login registry.redhat.io`
(requires a Red Hat subscription) before building.

```bash
make build IMAGE=quay.io/<your-org>/docling-event-driven-example:0.1.0
make push  IMAGE=quay.io/<your-org>/docling-event-driven-example:0.1.0
make deploy IMAGE=quay.io/<your-org>/docling-event-driven-example:0.1.0 NAMESPACE=docling
```

Or via Helm directly, passing your S3 endpoint/credentials:

```bash
helm upgrade --install docling-eventing deploy/helm -n docling --create-namespace \
  --set image.repository=quay.io/<your-org>/docling-event-driven-example \
  --set image.tag=0.1.0 \
  --set s3.endpoint=https://s3.example.com \
  --set s3.accessKeyId=... \
  --set s3.secretAccessKey=...
```

Then post a `com.docling.document.ingest` CloudEvent to the namespace's
Broker (see `tests/test_send_cloud_event.py` for the exact shape), or wire
your storage provider's bucket-notification mechanism to do it for you.

## Notes

- This example is deliberately vendor-neutral (plain S3 API via `boto3`),
  so it works against MinIO, ODF/Noobaa, or AWS S3 without modification —
  just point `s3.endpoint` at whichever one you're using.
- The output Channel here is an in-memory `InMemoryChannel` for simplicity.
  For anything beyond a demo, swap in a durable channel implementation
  (e.g. Kafka) so completion events survive a pod restart.
- Same image-size tradeoff as `serverless-api-example/`: this uses a
  public UBI base with Docling installed at build time. Pre-bake the model
  cache into your image if cold-start latency on first request matters.
