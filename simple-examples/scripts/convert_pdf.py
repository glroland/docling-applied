#!/usr/bin/env python3
"""Convert a local PDF to Markdown and JSON using the Docling SDK directly.

Usage:
    python convert_pdf.py <path/to/file.pdf> [output_dir]
"""

import json
import sys
from pathlib import Path

from docling.document_converter import DocumentConverter


def convert(input_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    converter = DocumentConverter()
    result = converter.convert(str(input_path))

    md_path = output_dir / f"{input_path.stem}.md"
    md_path.write_text(result.document.export_to_markdown(), encoding="utf-8")

    json_path = output_dir / f"{input_path.stem}.json"
    json_path.write_text(
        json.dumps(result.document.export_to_dict(), indent=2), encoding="utf-8"
    )

    print(f"Markdown written to {md_path}")
    print(f"JSON written to {json_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path/to/file.pdf> [output_dir]", file=sys.stderr)
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("output")
    convert(input_path, output_dir)
