# Batch via Pipeline

**Folder:** [`batch-via-pipeline-example/`](../batch-via-pipeline-example/) · **Pattern:** Data Science Pipeline (Kubeflow Pipelines)

## Overview

Convert a whole bucket of documents in one run, orchestrated as an
OpenShift AI **Data Science Pipeline** (Kubeflow Pipelines v2). This is
the pattern for "reprocess our document corpus" or "nightly ingestion
job" rather than a single on-demand conversion — and it's the same shape
Red Hat's own published production-RAG reference architecture uses for
the parsing stage (Docling + Data Science Pipelines, with Ray/Milvus/vLLM
layered on top for the full RAG case).

## How it works

```
list_objects(bucket, prefix) ──► [object keys]
        │
        ▼  dsl.ParallelFor (one branch per object, `parallelism` wide)
  download_object
        │
        ▼
  run_docling (GPU branch if use_gpu, else CPU branch — dsl.If/dsl.Else)
        │
        ▼
  upload_directory(output_bucket, output_prefix)
```

`run_docling` is a `dsl.container_component` that runs the `docling` CLI
inside the `docling-serve` CPU/CUDA image (the same image family as
[Docling Serve](docling-serve.md), just invoked as a CLI rather than a
REST API). It's invoked once per branch because KFP resource requests
(accelerator limits, node selectors) are set at pipeline-authoring time,
not as a runtime value.

## Prerequisites

- An OpenShift AI Data Science Project with Data Science Pipelines enabled
- An S3-compatible bucket for input and output (MinIO, ODF/Noobaa, or AWS
  S3)
- A Kubernetes Secret shaped like an OpenShift AI **Data Connection**
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_ENDPOINT`,
  `AWS_DEFAULT_REGION`) — create one via **Data connections > Add data
  connection** in your Data Science Project
- GPU-enabled worker nodes with the NVIDIA GPU operator, only if
  `use_gpu=true`

## Repository layout

| Path | Purpose |
|---|---|
| `pipeline.py` | The full KFP v2 pipeline: `list_objects`, `download_object`, `run_docling`, `upload_directory` components + the `docling_batch_pipeline` DAG |
| `requirements.txt` | `kfp`, `kfp-kubernetes` (pipeline-authoring dependencies) |

## Usage

```bash
pip install -r batch-via-pipeline-example/requirements.txt
python batch-via-pipeline-example/pipeline.py docling-batch-pipeline.yaml
```

Import the compiled YAML via the OpenShift AI dashboard (**Data Science
Pipelines > Pipelines > Import pipeline**), or submit it with the `kfp`
client:

```python
from kfp.client import Client

client = Client(host="<data-science-pipelines-route>")
client.create_run_from_pipeline_package(
    "docling-batch-pipeline.yaml",
    arguments={
        "input_bucket": "raw-documents",
        "input_prefix": "incoming/",
        "output_bucket": "converted-documents",
        "output_prefix": "converted/",
        "use_gpu": False,
        "parallelism": 4,
    },
)
```

Via the root Makefile: `make build-batch-via-pipeline-example` compiles
to `target/batch-via-pipeline-example/`; `make deploy-batch-via-pipeline-example
PIPELINES_ENDPOINT=<route>` submits a run.

## Configuration reference

| Pipeline parameter | Default | Purpose |
|---|---|---|
| `input_bucket` | *(required)* | Source bucket |
| `input_prefix` | `""` | Source prefix/folder |
| `output_bucket` | *(required)* | Destination bucket |
| `output_prefix` | `"converted/"` | Destination prefix |
| `use_gpu` | `False` | Routes `run_docling` to the GPU branch (`device=cuda`, `nvidia.com/gpu` accelerator limit) |
| `parallelism` | `4` | Concurrent `dsl.ParallelFor` branches |

`DATA_CONNECTION_SECRET_NAME` and the `docling-serve` CPU/GPU image
references are constants at the top of `pipeline.py` — edit them directly
rather than exposing them as pipeline parameters, since they're
environment-specific rather than per-run.

## When to use this

- Converting many documents in one batch rather than one at a time.
- Scheduled/repeatable ingestion (nightly reprocessing, backfills).
- You want the same shape as OpenShift AI's own published production-RAG
  reference architecture, ready to extend with the Ray/Milvus/vLLM layers
  it describes.

**Not** for: a single document converted on demand in response to a
client request — see [Docling Serve](docling-serve.md). Not for reacting
automatically to individual file uploads — see
[Event-Driven](event-driven-example.md).
