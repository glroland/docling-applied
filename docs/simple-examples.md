# Simple Examples

**Folder:** [`simple-examples/`](../simple-examples/) · **Pattern:** Docling SDK, called directly · **Recommended starting point**

## Overview

The Docling Python SDK used inline — no REST service, no pipeline, no
cluster infrastructure. `DocumentConverter().convert(source)` accepts a
local file path or a URL and returns a `DoclingDocument` you can export
as Markdown or JSON, regardless of whether the source was a PDF, DOCX,
PPTX, XLSX, HTML page, or image. This is the fastest way to build an
accurate mental model of what Docling does before adopting any of the
other patterns in this repo — every other example is this same SDK call,
just wrapped in a service, pipeline, or event handler.

## How it works

```
DocumentConverter().convert(source)
        │
        ▼
  DoclingDocument  ──► export_to_markdown()
        │           ──► export_to_dict()  (JSON)
        ▼
  HybridChunker().chunk(dl_doc=...)  ──► structure-aware chunks for RAG
```

Docling auto-detects the input format and routes it through the
appropriate pipeline: native text extraction for born-digital PDFs and
office documents, layout analysis plus OCR for scanned pages and images.
No pipeline options are set in these examples, so Docling uses its
defaults (CPU inference, on-demand OCR).

## Prerequisites

- Python 3.11+ (or an OpenShift AI workbench)
- `pip install -r simple-examples/requirements.txt` (pulls Docling from
  the repo's central version pin — see [the root docs index](README.md#shared-conventions))

## Repository layout

| Path | Purpose |
|---|---|
| `notebooks/docling_quickstart.ipynb` | Guided walkthrough: PDF, scanned PDF, image, web page, chunking |
| `scripts/convert_pdf.py` | Convert a local PDF to `.md` + `.json` |
| `scripts/convert_image.py` | Convert a local image (PNG/JPEG/TIFF) |
| `scripts/convert_webpage.py` | Convert a live URL |
| `scripts/chunking.py` | Convert + split into `HybridChunker` chunks |

## Usage

```bash
pip install -r simple-examples/requirements.txt

python simple-examples/scripts/convert_pdf.py samples/structured.pdf output/
python simple-examples/scripts/convert_pdf.py samples/scanned.pdf output/   # OCR runs automatically
python simple-examples/scripts/convert_webpage.py https://docling-project.github.io/docling/ output/
python simple-examples/scripts/chunking.py samples/hybrid.pdf output/
```

Or open `notebooks/docling_quickstart.ipynb` in an OpenShift AI workbench
and run the cells in order.

Via the root Makefile: `make test-simple-examples` (writes to `target/simple-examples/`).

## Configuration reference

There isn't one — that's the point of this example. `DocumentConverter()`
is called with no arguments, so every option is Docling's default. To see
what production tuning looks like (GPU acceleration, OCR engine choice,
page batch size, image export mode), see
[Serverless API](serverless-api-example.md) or
[Batch via Pipeline](batch-via-pipeline-example.md), both of which set
these explicitly.

## When to use this

- You're evaluating Docling and want to see real output on real documents
  with the least possible setup.
- You're prototyping in a notebook/workbench before committing to a
  deployment shape.
- You need the chunking step (`HybridChunker`) as a building block for a
  RAG pipeline — see [RAG via OGX](rag-via-ogx-example.md) for where those
  chunks go next.

**Not** for: anything that needs to run as a service other code calls
over the network — see [Docling Serve](docling-serve.md) for that.
