# simple-examples

The "hello world" of Docling: call the Python SDK directly, no service, no
pipeline, no cluster infrastructure. Use this to build intuition for what
Docling does before moving on to any of the deployed patterns in this repo.

Run it in an OpenShift AI workbench, or any Python 3.11+ environment.

## What's here

- `notebooks/docling_quickstart.ipynb` — walk through converting a
  structured PDF, a scanned PDF, an image, and a live web page to Markdown
  and JSON, then chunking a document for RAG. Start here.
- `scripts/convert_pdf.py` — convert a local PDF to `.md` + `.json`
- `scripts/convert_image.py` — convert a local image (PNG/JPEG/TIFF)
- `scripts/convert_webpage.py` — convert a live URL
- `scripts/chunking.py` — convert + split into structure-aware chunks with
  `HybridChunker` (the input shape used by
  `pending-redhat-testing/rag-via-ogx-example/`)

## Running the scripts

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python scripts/convert_pdf.py ../samples/structured.pdf output/
python scripts/convert_pdf.py ../samples/scanned.pdf output/   # OCR runs automatically
python scripts/convert_webpage.py https://docling-project.github.io/docling/ output/
python scripts/chunking.py ../samples/hybrid.pdf output/
```

## What you're seeing

`DocumentConverter().convert(source)` accepts a local file path or a URL and
auto-detects the format. It returns a `ConversionResult` whose `.document`
is a `DoclingDocument` — a unified representation you can export as
Markdown (`export_to_markdown()`) or a JSON-serializable dict
(`export_to_dict()`), regardless of whether the source was a PDF, DOCX,
PPTX, XLSX, HTML page, or image.

No pipeline options are set here, so Docling uses its defaults (CPU
inference, on-demand OCR for pages without a text layer). The other
examples in this repo show how to tune that — GPU acceleration, OCR engine
choice, batch size — for production use:

- `docling-serve/` + `docling-serve-examples/` — same conversion, behind a
  REST API
- `batch-via-pipeline-example/` — the same SDK calls, run as a Data Science
  Pipeline over many documents
- `pending-redhat-testing/serverless-api-example/` — a custom microservice
  with GPU/OCR tuning exposed as config
