#!/usr/bin/env python3
"""Convert a live web page by URL via docling-serve's /v1/convert/source.

Usage:
    python convert_webpage.py <page-url> <docling-serve-url> [output_dir]
"""

import json
import re
import sys
from pathlib import Path

import requests


def _slug(url: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "-", url).strip("-")[:60] or "page"


def convert(page_url: str, base_url: str, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    resp = requests.post(
        f"{base_url}/v1/convert/source",
        json={
            "options": {"to_formats": ["md", "json"]},
            "sources": [{"kind": "http", "url": page_url}],
        },
        timeout=300,
    )
    resp.raise_for_status()
    document = resp.json()["document"]

    stem = _slug(page_url)

    md_path = output_dir / f"{stem}.md"
    md_path.write_text(document["md_content"], encoding="utf-8")

    json_path = output_dir / f"{stem}.json"
    json_path.write_text(json.dumps(document["json_content"], indent=2), encoding="utf-8")

    print(f"Markdown written to {md_path}")
    print(f"JSON written to {json_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <page-url> <docling-serve-url> [output_dir]", file=sys.stderr)
        sys.exit(1)

    page_url = sys.argv[1]
    base_url = sys.argv[2].rstrip("/")
    output_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("output")
    convert(page_url, base_url, output_dir)
