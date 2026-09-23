import json
import os
import tempfile
from pathlib import Path

import boto3
import httpx
import uvicorn
from cloudevents.v1.conversion import to_structured
from cloudevents.v1.http import CloudEvent, from_http
from docling.document_converter import DocumentConverter
from fastapi import FastAPI, Request, Response

# Output channel URL — the Knative Channel this function publishes its
# completion event to. Update to match your cluster/namespace, or leave the
# default which matches deploy/helm/templates/channel-output.yaml.
OUTPUT_CHANNEL_URL = os.environ.get(
    "OUTPUT_CHANNEL_URL",
    "http://docling-process-output-kn-channel.docling.svc.cluster.local",
)

S3_ENDPOINT_URL = os.environ.get("AWS_S3_ENDPOINT")
S3_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

app = FastAPI()


def _s3_client():
    return boto3.client("s3", endpoint_url=S3_ENDPOINT_URL, region_name=S3_REGION)


def parse_event_data(event) -> dict:
    """Extract and JSON-decode the CloudEvent data payload."""
    data = event.data
    if isinstance(data, (bytes, bytearray)):
        data = data.decode("utf-8")
    if isinstance(data, str):
        data = json.loads(data)
    return data


def validate_payload(data: dict) -> tuple[dict, dict]:
    """Validate that the payload contains input and output object references."""
    if "input" not in data or "output" not in data:
        raise ValueError("Payload must contain 'input' and 'output' fields")

    inp = data["input"]
    out = data["output"]

    for field in ("bucket", "key"):
        if field not in inp:
            raise ValueError(f"'input' is missing required field: '{field}'")
        if field not in out:
            raise ValueError(f"'output' is missing required field: '{field}'")

    return inp, out


def download_object(client, bucket: str, key: str, dest: Path) -> None:
    client.download_file(bucket, key, str(dest))
    print(f"[S3] Downloaded {bucket}/{key} -> {dest}")


def upload_directory(client, bucket: str, prefix: str, src_dir: Path) -> None:
    for file in src_dir.rglob("*"):
        if file.is_file():
            relative = file.relative_to(src_dir)
            object_key = f"{prefix.rstrip('/')}/{relative}"
            client.upload_file(str(file), bucket, object_key)
            print(f"[S3] Uploaded {file} -> {bucket}/{object_key}")


@app.post("/")
async def handle_event(request: Request) -> Response:
    body = await request.body()
    event = from_http(request.headers, body)

    print(f"[CloudEvent received] id={event['id']} type={event['type']} source={event['source']}")

    try:
        data = parse_event_data(event)
        print(f"[Payload] {data}")

        inp, out = validate_payload(data)
        print(f"[Input]  bucket={inp['bucket']} key={inp['key']}")
        print(f"[Output] bucket={out['bucket']} key={out['key']}")

    except (ValueError, json.JSONDecodeError, KeyError) as exc:
        print(f"[Error] Invalid payload: {exc}")
        return Response(status_code=400, content=str(exc))

    s3 = _s3_client()

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        input_file = tmp / Path(inp["key"]).name
        output_dir = tmp / "output"
        output_dir.mkdir()

        download_object(s3, inp["bucket"], inp["key"], input_file)

        print(f"[Docling] Converting {input_file}")
        converter = DocumentConverter()
        result = converter.convert(str(input_file))

        stem = input_file.stem
        (output_dir / f"{stem}.md").write_text(
            result.document.export_to_markdown(), encoding="utf-8"
        )
        (output_dir / f"{stem}.json").write_text(
            json.dumps(result.document.export_to_dict(), indent=2), encoding="utf-8"
        )
        print(f"[Docling] Conversion complete, artifacts written to {output_dir}")

        upload_directory(s3, out["bucket"], out["key"], output_dir)

    result_event = CloudEvent(
        {
            "type": "com.docling.document.processed",
            "source": "docling-process-function",
        },
        {
            "input": inp,
            "output": out,
            "status": "success",
        },
    )
    headers, result_body = to_structured(result_event)
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(OUTPUT_CHANNEL_URL, headers=headers, content=result_body, timeout=10)
        print(f"[Published] status={resp.status_code} channel={OUTPUT_CHANNEL_URL}")
    except httpx.RequestError as exc:
        print(f"[Publish failed] {exc}")

    return Response(status_code=200)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
