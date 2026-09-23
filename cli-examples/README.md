# cli-examples

The `docling` command-line tool, no Python required. It ships as part of
the `docling` package (`pip install docling` gives you the `docling`
command directly) and does everything the SDK does in
[`simple-examples/`](../simple-examples/) — this is the shell-scripting
equivalent, useful for one-off conversions, quick checks, or wiring
Docling into a larger shell pipeline without writing any Python.

## What's here

| Script | Demonstrates |
|---|---|
| `scripts/convert_to_markdown.sh` | Convert a file to Markdown |
| `scripts/convert_to_json.sh` | Convert a file to Docling JSON |
| `scripts/convert_multi_format.sh` | One call, multiple output formats (`--to` repeated) |
| `scripts/convert_webpage.sh` | Convert a live URL — `docling` accepts a URL as the source directly |
| `scripts/convert_scanned_with_ocr.sh` | Force a specific OCR engine (rapidocr) for scanned/image-only input |
| `scripts/chunk_document.sh` | Convert straight to structure-aware chunks (`--to chunks`), no Python |

## Usage

```bash
pip install -r requirements.txt   # installs docling, and the `docling` CLI with it

./scripts/convert_to_markdown.sh ../samples/structured.pdf output/
./scripts/convert_scanned_with_ocr.sh ../samples/scanned.pdf output/
./scripts/convert_webpage.sh https://docling-project.github.io/docling/ output/
./scripts/chunk_document.sh ../samples/hybrid.pdf output/
```

Each script takes the input (a file path or, for `convert_webpage.sh`, a
URL) as `$1` and an output directory as `$2` (defaults to `output/` if
omitted).

## What you're seeing

Every script is a thin wrapper around one `docling` invocation:

```bash
docling --to md --output "$OUTPUT_DIR" "$INPUT"
```

`--to` can be repeated to produce several formats from a single parse
(`convert_multi_format.sh`); valid values include `md`, `json`, `text`,
`html`, `doctags`, and `chunks` (structure-aware chunks via
`--chunks-type`, default `hybrid` — the same chunker
`simple-examples/scripts/chunking.py` uses via the SDK). `--from`
restricts which input formats are accepted; omitted here since Docling
auto-detects. Run `docling --help` for the full flag reference (OCR engine
selection, page ranges, accelerator device, table mode, and more —
`batch-via-pipeline-example/` uses several of these for GPU/CPU routing).
