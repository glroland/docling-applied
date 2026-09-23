# batch-via-pipeline-example

Convert a whole bucket of documents in one run, orchestrated as an
OpenShift AI **Data Science Pipeline** (Kubeflow Pipelines v2). This is the
pattern to reach for once you're past "convert one file" and into
"reprocess our document corpus" or "nightly ingestion job" — and it's the
same shape Red Hat's own published production-RAG reference architecture
uses for the parsing stage.

## What it does

For every object under `input_prefix` in `input_bucket`:

1. Download it (`list_objects` / `download_object`)
2. Convert it with the Docling CLI, GPU or CPU depending on `use_gpu`
   (`run_docling`)
3. Upload the resulting `.md` and `.json` to `output_bucket`/`output_prefix`
   (`upload_directory`)

Steps run in parallel across objects via `dsl.ParallelFor` (tune with the
`parallelism` pipeline parameter).

## Prerequisites

- An OpenShift AI Data Science Project with Data Science Pipelines enabled
- An S3-compatible bucket for input and output (MinIO, ODF/Noobaa, or AWS
  S3) reachable from the cluster
- If `use_gpu=true`, GPU-enabled worker nodes with the NVIDIA GPU operator

## Credentials

The pipeline reads S3 credentials from a Kubernetes Secret shaped like an
OpenShift AI **Data Connection** (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_S3_ENDPOINT`, `AWS_DEFAULT_REGION`). Easiest
path: in your Data Science Project, go to **Data connections > Add data
connection**, point it at your bucket, then set
`DATA_CONNECTION_SECRET_NAME` in `pipeline.py` to the secret name it
creates (visible via `oc get secrets`). You can use the same bucket for
input and output, or two separate data connections/buckets.

## Compile and run

```bash
pip install -r requirements.txt
python pipeline.py   # writes docling-batch-pipeline.yaml
```

Import `docling-batch-pipeline.yaml` via the OpenShift AI dashboard
(**Data Science Pipelines > Pipelines > Import pipeline**), or submit it
with the `kfp` client:

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

## Notes

- **Image**: components use the public `docling-serve` CPU/CUDA images
  (they bundle the `docling` CLI, not just the API server) so this runs
  on any cluster out of the box. If your OpenShift AI 3.5 installation
  provides the purpose-built `docling-sdk-cuda-ubi9` base image, swap it
  in for `DOCLING_GPU_IMAGE`/`DOCLING_CPU_IMAGE` — it's smaller since it
  skips the REST API layer entirely.
- **GPU/CPU branching**: `run_docling` is invoked once per branch
  (`dsl.If`/`dsl.Else`) because KFP resource requests (accelerator limits,
  node selectors) are set on the task at pipeline-authoring time, not as a
  runtime value — see `pipeline.py` for the pattern if you need to add a
  third branch (e.g. a "detect scanned vs. text PDF and route accordingly"
  step, as a fully automatic GPU/CPU split).
- **Caching is disabled** on every task here because they all depend on
  external bucket state that KFP can't see — re-running the pipeline
  should always re-list and re-convert.
- Verify `pipeline.py` compiles against the `kfp`/`kfp-kubernetes` versions
  your Data Science Pipelines engine actually runs before relying on it —
  a couple of the APIs used here (`dsl.If`/`dsl.OneOf`,
  `kubernetes.use_secret_as_env`) have shifted across `kfp` 2.x minor
  versions.
