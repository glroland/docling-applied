#!/usr/bin/env python3
"""Asynchronous file conversion: submit, poll, fetch the result.

Usage:
    python convert_file_async.py <file> <docling-serve-url> [output_dir]
"""

import json
import sys
import time
from pathlib import Path

import requests

POLL_INTERVAL_SECONDS = 5


def convert(input_path: Path, base_url: str, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(input_path, "rb") as f:
        submit_resp = requests.post(
            f"{base_url}/v1/convert/file/async",
            files={"files": (input_path.name, f)},
            data={
                "to_formats": "md,json",
                "do_ocr": "true",
                "image_export_mode": "placeholder",
                "table_mode": "fast",
                "abort_on_error": "false",
            },
            timeout=60,
        )
    submit_resp.raise_for_status()
    task_id = submit_resp.json()["task_id"]
    print(f"Task submitted: {task_id}")

    while True:
        poll_resp = requests.get(f"{base_url}/v1/status/poll/{task_id}", timeout=30)
        poll_resp.raise_for_status()
        status = poll_resp.json()["task_status"]
        print(f"Status: {status}")

        if status == "success":
            break
        if status == "failure":
            raise RuntimeError(f"Conversion failed: {poll_resp.json()}")

        time.sleep(POLL_INTERVAL_SECONDS)

    result_resp = requests.get(f"{base_url}/v1/result/{task_id}", timeout=60)
    result_resp.raise_for_status()
    document = result_resp.json()["document"]

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
