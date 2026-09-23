#!/usr/bin/env python3
"""Convert a live web page to Markdown and JSON using Docling.

Docling fetches the URL itself and runs the same layout-aware conversion it
uses for HTML files on disk.

Usage:
    python convert_webpage.py <https://example.com/article> [output_dir]
"""

import json
import re
import sys
from pathlib import Path

from docling.document_converter import DocumentConverter


def _slug(url: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "-", url).strip("-")[:60] or "page"


def convert(url: str, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    converter = DocumentConverter()
    result = converter.convert(url)

    stem = _slug(url)

    md_path = output_dir / f"{stem}.md"
    md_path.write_text(result.document.export_to_markdown(), encoding="utf-8")

    json_path = output_dir / f"{stem}.json"
    json_path.write_text(
        json.dumps(result.document.export_to_dict(), indent=2), encoding="utf-8"
    )

    print(f"Markdown written to {md_path}")
    print(f"JSON written to {json_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <url> [output_dir]", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("output")
    convert(url, output_dir)
