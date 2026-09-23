"""Batch document conversion as an OpenShift AI Data Science Pipeline.

For every object under a prefix in an S3-compatible bucket: download it,
convert it with Docling (GPU or CPU), and upload the Markdown/JSON output
back to a different bucket/prefix.

This mirrors the reference architecture Red Hat has published for
production RAG ingestion on OpenShift AI (Docling + Data Science Pipelines,
with Ray/Milvus/vLLM layered on top for the full RAG case — see
rag-via-ogx-example/ for that next step).

Compile:
    python pipeline.py [output_path]
    # Defaults to ./docling-batch-pipeline.yaml; pass an explicit path
    # (the root Makefile points this at target/) to compile elsewhere.
    # Upload/import the result as a Pipeline in the OpenShift AI Data
    # Science Pipelines UI, or run it with the kfp client.

Credentials:
    Bucket access comes from a Kubernetes Secret in the pipeline's
    namespace matching the shape of an OpenShift AI "Data Connection"
    (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_S3_ENDPOINT,
    AWS_DEFAULT_REGION). Set DATA_CONNECTION_SECRET_NAME below to the
    secret created when you add a Data Connection to your Data Science
    Project (Project > Data connections), or create one yourself with
    those four keys.
"""

from kfp import compiler, dsl, kubernetes
from kfp.dsl import Artifact, Dataset, Input, Output

DOCLING_CPU_IMAGE = "ghcr.io/docling-project/docling-serve-cpu:latest"
# CUDA images are not published under `latest` — pin an explicit release.
# Check https://github.com/docling-project/docling-serve/pkgs/container/docling-serve-cu128
DOCLING_GPU_IMAGE = "ghcr.io/docling-project/docling-serve-cu128:v1.8.0"

DATA_CONNECTION_SECRET_NAME = "aws-connection-docling-pipeline"
_S3_ENV = {
    "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
    "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
    "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
}


@dsl.component(base_image="python:3.11-slim", packages_to_install=["boto3"])
def list_objects(bucket: str, prefix: str) -> list:
    import os

    import boto3

    s3 = boto3.client(
        "s3",
        endpoint_url=os.environ["AWS_S3_ENDPOINT"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    )
    keys = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if not obj["Key"].endswith("/"):
                keys.append(obj["Key"])
    return keys


@dsl.component(base_image="python:3.11-slim", packages_to_install=["boto3"])
def download_object(bucket: str, key: str, output_file: Output[Artifact]):
    import os

    import boto3

    s3 = boto3.client(
        "s3",
        endpoint_url=os.environ["AWS_S3_ENDPOINT"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    )
    s3.download_file(bucket, key, output_file.path)


@dsl.container_component
def run_docling(
    source_document: Input[Artifact],
    device: str,
    output_dir: Output[Dataset],
):
    return dsl.ContainerSpec(
        image=DOCLING_GPU_IMAGE if device == "cuda" else DOCLING_CPU_IMAGE,
        command=["docling"],
        args=[
            "--from",
            "pdf",
            "--to",
            "md",
            "--to",
            "json",
            "--image-export-mode",
            "placeholder",
            "--device",
            device,
            "--output",
            output_dir.path,
            source_document.path,
        ],
    )


@dsl.component(base_image="python:3.11-slim", packages_to_install=["boto3"])
def upload_directory(bucket: str, prefix: str, input_dir: Input[Dataset]):
    import os
    from pathlib import Path

    import boto3

    s3 = boto3.client(
        "s3",
        endpoint_url=os.environ["AWS_S3_ENDPOINT"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    )
    src_dir = Path(input_dir.path)
    for file in src_dir.rglob("*"):
        if file.is_file():
            relative = file.relative_to(src_dir)
            s3.upload_file(str(file), bucket, f"{prefix.rstrip('/')}/{relative}")


def _with_s3_creds(task):
    return kubernetes.use_secret_as_env(
        task, secret_name=DATA_CONNECTION_SECRET_NAME, secret_key_to_env=_S3_ENV
    )


@dsl.pipeline(name="Docling Batch Ingestion Pipeline")
def docling_batch_pipeline(
    input_bucket: str,
    input_prefix: str = "",
    output_bucket: str = "",
    output_prefix: str = "converted/",
    use_gpu: bool = False,
    parallelism: int = 4,
):
    list_task = _with_s3_creds(
        list_objects(bucket=input_bucket, prefix=input_prefix)
    )
    list_task.set_caching_options(enable_caching=False)

    with dsl.ParallelFor(items=list_task.output, parallelism=parallelism) as object_key:
        download_task = _with_s3_creds(
            download_object(bucket=input_bucket, key=object_key)
        )
        download_task.set_caching_options(enable_caching=False)

        with dsl.If(use_gpu == True):  # noqa: E712
            gpu_task = run_docling(
                source_document=download_task.outputs["output_file"],
                device="cuda",
            )
            gpu_task.set_cpu_limit("4")
            gpu_task.set_memory_limit("8Gi")
            gpu_task.add_node_selector_constraint("nvidia.com/gpu.present")
            gpu_task.set_accelerator_type("nvidia.com/gpu")
            gpu_task.set_accelerator_limit(1)
            gpu_task.set_caching_options(enable_caching=False)

        with dsl.Else():
            cpu_task = run_docling(
                source_document=download_task.outputs["output_file"],
                device="cpu",
            )
            cpu_task.set_cpu_limit("4")
            cpu_task.set_memory_limit("8Gi")
            cpu_task.set_caching_options(enable_caching=False)

        docling_output = dsl.OneOf(
            gpu_task.outputs["output_dir"], cpu_task.outputs["output_dir"]
        )

        upload_task = _with_s3_creds(
            upload_directory(
                bucket=output_bucket,
                prefix=output_prefix,
                input_dir=docling_output,
            )
        )
        upload_task.set_caching_options(enable_caching=False)


if __name__ == "__main__":
    import sys

    # Default keeps this runnable standalone; the root Makefile always
    # passes an explicit path under target/ so nothing is written here.
    package_path = sys.argv[1] if len(sys.argv) > 1 else "docling-batch-pipeline.yaml"
    compiler.Compiler().compile(
        pipeline_func=docling_batch_pipeline,
        package_path=package_path,
    )
    print(f"Compiled {package_path}")
