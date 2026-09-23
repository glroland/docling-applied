# CLI Examples

**Folder:** [`cli-examples/`](../cli-examples/) · **Pattern:** The `docling` command-line tool

## Overview

The `docling` command-line tool, installed automatically alongside the
Python package (`pip install docling` gives you the `docling` command
directly). It does everything the SDK does in
[Simple Examples](simple-examples.md), but from a shell script — useful
for one-off conversions, quick checks, or wiring Docling into a larger
shell pipeline (CI, cron job, glue script) without writing any Python.

## How it works

Every script here is a thin wrapper around one `docling` invocation:

```bash
docling --to md --output "$OUTPUT_DIR" "$INPUT"
```

`--to` can be repeated to produce several formats from a single parse.
Valid values include `md`, `json`, `text`, `html`, `doctags`, and
`chunks` (structure-aware chunks via `--chunks-type`, default `hybrid` —
the same chunker the SDK's `HybridChunker` uses). `--from` restricts
accepted input formats; it's omitted in these scripts since Docling
auto-detects. The source argument accepts a local file, a directory, or
a URL directly.

## Prerequisites

- Python 3.11+ with `pip install -r cli-examples/requirements.txt`
  (installs Docling, and the `docling` CLI with it)

## Repository layout

| Script | Demonstrates |
|---|---|
| `scripts/convert_to_markdown.sh` | Convert a file to Markdown |
| `scripts/convert_to_json.sh` | Convert a file to Docling JSON |
| `scripts/convert_multi_format.sh` | One call, multiple output formats (`--to` repeated) |
| `scripts/convert_webpage.sh` | Convert a live URL |
| `scripts/convert_scanned_with_ocr.sh` | Force a specific OCR engine (rapidocr) for scanned/image-only input |
| `scripts/chunk_document.sh` | Convert straight to structure-aware chunks (`--to chunks`) |

## Usage

```bash
pip install -r cli-examples/requirements.txt

cli-examples/scripts/convert_to_markdown.sh samples/structured.pdf output/
cli-examples/scripts/convert_scanned_with_ocr.sh samples/scanned.pdf output/
cli-examples/scripts/convert_webpage.sh https://docling-project.github.io/docling/ output/
cli-examples/scripts/chunk_document.sh samples/hybrid.pdf output/
```

Each script takes the input (a file path, or a URL for
`convert_webpage.sh`) as `$1` and an output directory as `$2` (defaults
to `output/`).

Via the root Makefile: `make test-cli-examples` (writes to `target/cli-examples/`).

## Configuration reference

Run `docling --help` for the full flag reference. Flags used across these
scripts:

| Flag | Purpose |
|---|---|
| `--to <format>` (repeatable) | Output format(s): `md`, `json`, `text`, `html`, `doctags`, `chunks`, ... |
| `--from <format>` | Restrict accepted input formats (omitted here — auto-detected) |
| `--ocr` / `--no-ocr` | Force or skip OCR |
| `--ocr-engine <name>` | OCR engine to use (e.g. `rapidocr`) |
| `--chunks-type <name>` | Chunker for `--to chunks` (default `hybrid`) |
| `--image-export-mode <mode>` | `embedded`, `placeholder`, or `referenced` |
| `--device <cpu\|cuda\|mps>` | Accelerator device (see [Batch via Pipeline](batch-via-pipeline-example.md) for GPU/CPU routing) |
| `--output <dir>` | Output directory |

## When to use this

- A one-off conversion from a terminal, without writing a Python script.
- Wiring Docling into an existing shell-based pipeline, CI job, or cron
  task where introducing a Python dependency isn't worth it.
- Quickly checking what a given document converts to before writing
  application code around it.

**Not** for: anything programmatic that needs to inspect or manipulate
the `DoclingDocument` object itself (chunk metadata, table structure,
etc.) — use the SDK ([Simple Examples](simple-examples.md)) for that.
