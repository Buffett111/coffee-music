#!/usr/bin/env python3
"""Verify CoffeeSync's bundled ShazamIO runtime without a network request."""

from __future__ import annotations

import importlib.metadata
import json
import shutil
import warnings

warnings.filterwarnings("ignore", message="Couldn't find ffmpeg or avconv.*")

import shazamio  # noqa: E402
import shazamio_core  # noqa: E402
from shazamio import Shazam  # noqa: E402,F401


def main() -> None:
    print(
        json.dumps(
            {
                "status": "ok",
                "shazamio": importlib.metadata.version("shazamio"),
                "shazamioCore": importlib.metadata.version("shazamio-core"),
                "ffmpegOnPath": shutil.which("ffmpeg") is not None,
                "networkRequestMade": False,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
