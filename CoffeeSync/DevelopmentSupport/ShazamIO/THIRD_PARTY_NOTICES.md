# Third-party notices

This directory is a development-only, self-contained runtime bundled by the
`shazamio-dev-baseline` branch.

- CPython 3.10.20 portable runtime: Python Software Foundation License.
- ShazamIO 0.8.1: MIT License, <https://github.com/shazamio/ShazamIO>.
- shazamio-core 1.1.2: MIT License, <https://github.com/shazamio/shazamio-core>.
- ytmusicapi 1.12.1: MIT License, <https://github.com/sigma67/ytmusicapi>.

The Python package metadata and license material for all installed transitive
dependencies is retained under `python/lib/python3.10/site-packages/*-dist-info`.
ShazamIO communicates with an undocumented Shazam endpoint; this is not an
official Shazam SDK or production integration.
ytmusicapi emulates YouTube Music web requests; it is not supported or endorsed
by Google and is bundled only for this experimental resolver branch.
