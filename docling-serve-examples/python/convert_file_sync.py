#!/usr/bin/env python3
"""Synchronous file conversion against a running docling-serve deployment.

Usage:
    python convert_file_sync.py <file> <docling-serve-url> [output_dir]
"""

import json
import sys
from pathlib import Path

import requests


def convert(input_path: Path, base_url: str, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(input_path, "rb") as f:
        resp = requests.post(
            f"{base_url}/v1/convert/file",
            files={"files": (input_path.name, f)},
            # to_formats is a list field (docling's ConvertDocumentsOptions);
            # docling-serve's multipart form decoder only special-cases
            # dict/pydantic fields for JSON parsing, so a plain list field
            # needs one repeated form entry per value, not a comma-joined
            # string — requests does that for a list value in `data`.
            data={
                "to_formats": ["md", "json"],
                "do_ocr": "true",
                "image_export_mode": "placeholder",
                "table_mode": "fast",
                "abort_on_error": "false",
            },
            timeout=300,
        )
    resp.raise_for_status()
    document = resp.json()["document"]

    md_path = output_dir / f"{input_path.stem}.md"
    md_path.write_text(document["md_content"], encoding="utf-8")

    json_path = output_dir / f"{input_path.stem}.json"
    json_path.write_text(json.dumps(document["json_content"], indent=2), encoding="utf-8")

    print(f"Markdown written to {md_path}")
    print(f"JSON written to {json_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <file> <docling-serve-url> [output_dir]", file=sys.stderr)
        sys.exit(1)

    input_path = Path(sys.argv[1])
    base_url = sys.argv[2].rstrip("/")
    output_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("output")
    convert(input_path, base_url, output_dir)
