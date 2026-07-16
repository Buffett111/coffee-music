#!/usr/bin/env python3
"""Resolve a Shazam title/artist pair to canonical YouTube Music song entries.

This is deliberately a catalog resolver, not a playback client. CoffeeSync still
uses YouTube's official visible IFrame player for playback.
"""

from __future__ import annotations

import argparse
import json
import sys

from ytmusicapi import YTMusic


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title")
    parser.add_argument("artist")
    arguments = parser.parse_args()

    query = f"{arguments.title} {arguments.artist}".strip()
    try:
        results = YTMusic().search(
            query,
            filter="songs",
            limit=10,
            ignore_spelling=True,
        )
        candidates: list[dict[str, object]] = []
        for result in results:
            video_id = result.get("videoId")
            title = result.get("title")
            artists = result.get("artists") or []
            artist_names = [artist.get("name") for artist in artists if artist.get("name")]
            if not video_id or not title or not artist_names:
                continue
            album = result.get("album") or {}
            candidates.append(
                {
                    "videoID": video_id,
                    "title": title,
                    "artists": artist_names,
                    "album": album.get("name"),
                    "durationSeconds": result.get("duration_seconds"),
                    "resultType": result.get("resultType"),
                }
            )
        print(json.dumps({"query": query, "candidates": candidates}, ensure_ascii=False))
        return 0 if candidates else 2
    except Exception as error:
        print(json.dumps({"query": query, "candidates": [], "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
