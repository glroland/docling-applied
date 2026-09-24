"""Integration test: send a CloudEvent to the deployed docling-process Knative service.

Configuration via environment variables:
  CLUSTER_URL        Full service URL (e.g. https://docling-process-docling.apps.mycluster.example.com)
                     If set, OPENSHIFT_CLUSTER is ignored.
  OPENSHIFT_CLUSTER  Base apps domain (e.g. apps.mycluster.example.com). The service URL is
                     constructed as https://<kservice-name>-<namespace>.<OPENSHIFT_CLUSTER>.
  KSERVICE_NAME      Knative service name (default: docling-process)
  NAMESPACE          OpenShift namespace (default: docling)

Event payload schema:
  {
    "input":  { "bucket": "<input-bucket>", "key": "<object-key-of-file>" },
    "output": { "bucket": "<output-bucket>", "key": "<object-key-prefix>" }
  }
"""

import os
import uuid

import httpx
import pytest
from cloudevents.v1.conversion import to_structured
from cloudevents.v1.http import CloudEvent

KSERVICE_NAME = os.environ.get("KSERVICE_NAME", "docling-process")
NAMESPACE = os.environ.get("NAMESPACE", "docling")


def get_service_url() -> str:
    cluster_url = os.environ.get("CLUSTER_URL")
    if cluster_url:
        return cluster_url.rstrip("/")

    openshift_cluster = os.environ.get("OPENSHIFT_CLUSTER")
    if openshift_cluster:
        return f"https://{KSERVICE_NAME}-{NAMESPACE}.{openshift_cluster.lstrip('.')}"

    pytest.skip("No cluster address provided. Set CLUSTER_URL or OPENSHIFT_CLUSTER env var.")


@pytest.fixture(scope="session")
def service_url() -> str:
    return get_service_url()


def build_cloud_event(
    input_bucket: str = "docling-input",
    input_key: str = "documents/sample.pdf",
    output_bucket: str = "docling-output",
    output_key: str = "processed/sample/",
) -> tuple[dict, bytes]:
    data = {
        "input": {"bucket": input_bucket, "key": input_key},
        "output": {"bucket": output_bucket, "key": output_key},
    }
    event = CloudEvent(
        {
            "type": "com.docling.document.ingest",
            "source": "integration-test",
            "id": str(uuid.uuid4()),
        },
        data,
    )
    return to_structured(event)


class TestSendCloudEvent:
    def test_send_document_ingest_event(self, service_url: str):
        headers, body = build_cloud_event()

        with httpx.Client(verify=False, timeout=30) as client:
            response = client.post(service_url, headers=headers, content=body)

        assert response.status_code == 200, (
            f"Expected 200, got {response.status_code}. Body: {response.text}"
        )

    def test_send_invalid_payload_returns_400(self, service_url: str):
        event = CloudEvent(
            {
                "type": "com.docling.document.ingest",
                "source": "integration-test",
                "id": str(uuid.uuid4()),
            },
            {"input": {"bucket": "my-bucket", "key": "docs/file.pdf"}},
        )
        headers, body = to_structured(event)

        with httpx.Client(verify=False, timeout=30) as client:
            response = client.post(service_url, headers=headers, content=body)

        assert response.status_code == 400, (
            f"Expected 400, got {response.status_code}. Body: {response.text}"
        )
