#!/usr/bin/env python3
"""Development-only ShazamIO runner embedded in the CoffeeSync test branch."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path

from shazamio import Shazam


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio", type=Path)
    arguments = parser.parse_args()
    audio = arguments.audio.expanduser()
    if not audio.is_file():
        print(f"Audio file not found: {audio}", file=sys.stderr)
        return 64

    started = time.perf_counter()
    try:
        response = await Shazam().recognize(str(audio))
        matches = response.get("matches", [])
        track = response.get("track") or {}
        recognized = bool(matches and track)
        result: dict[str, object] = {
            "input": str(audio.resolve()),
            "recognized": recognized,
            "matchCount": len(matches),
            "latencyMs": round((time.perf_counter() - started) * 1000),
            "track": {
                "title": track.get("title"),
                "subtitle": track.get("subtitle"),
                "key": track.get("key"),
            }
            if recognized
            else None,
        }
        if matches:
            result["firstMatch"] = {
                "id": matches[0].get("id"),
                "offset": matches[0].get("offset"),
                "timeSkew": matches[0].get("timeskew"),
                "frequencySkew": matches[0].get("frequencyskew"),
            }
    except Exception as error:
        result = {
            "input": str(audio.resolve()),
            "recognized": False,
            "errorType": type(error).__name__,
            "error": str(error),
        }
        recognized = False

    print(json.dumps(result, ensure_ascii=False))
    return 0 if recognized else 2


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
