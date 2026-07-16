# CoffeeSync for macOS

CoffeeSync listens briefly through your Mac's built-in microphone, identifies
nearby music with the bundled ShazamIO runtime, then searches and starts a
matching visible YouTube player close to the matched position. It is a small,
personal non-commercial experiment for listening to a café's music through
headphones while reducing surrounding noise.

## Product scope

CoffeeSync has exactly one recognition and playback path:

```text
Mac built-in microphone
        |
  5 / 8 / 10 second WAV
        |
 bundled ShazamIO runtime
        |
 title + artist + matched offset
        |
 YouTube Data API v3 search
        |
 visible YouTube IFrame Player
```

It does **not** use ShazamKit, MusicKit, Apple Music, AudD, or a personal media
library. That means it does not need an Apple Developer Program membership to
build or run locally. The experimental resolver queries YouTube Music's
song-only catalog through the bundled `ytmusicapi` runtime, so it does not ask
users to enter, store, or share a YouTube Data API key.

## Install the DMG

1. Download `CoffeeSync-<version>.dmg` and `SHA256SUMS` from a release.
2. Optionally verify the download in Terminal:

   ```sh
   shasum -a 256 -c SHA256SUMS
   ```

3. Open the DMG and drag **CoffeeSync.app** onto **Applications**.
4. Open CoffeeSync from Applications. The first launch of an ad-hoc build may
   need Finder: Control-click the app, select **Open**, then confirm **Open**.
5. Allow Microphone access when you start syncing.

The distributed DMG is ad-hoc signed for integrity during local packaging. It
is not Developer ID-notarized unless a release maintainer additionally signs
and notarizes it with their own Apple credentials.

## First use

1. Launch CoffeeSync. No API key is requested or stored by the app.
2. Start with a **10 second** capture, press **Start sync**, and grant
   microphone permission. CoffeeSync prefers the Mac's built-in microphone so
   changing to headphones does not accidentally replace the room input.
3. Adjust **extra playback delay** (0–15 seconds) if the YouTube track is ahead
   of or behind the room. The selected capture length is already part of the
   initial position estimate; every slider adjustment immediately seeks the
   currently playing YouTube video by the changed amount.

Use **Test YouTube playback** to verify the resolver and visible player before
recording.

## Recognition cadence

- After an unrecognized clip or YouTube error, CoffeeSync retries after
  **18 seconds**.
- After a recognised track, it waits **60 seconds** before checking again.
- If the currently synced YouTube video reaches its end, CoffeeSync starts a
  fresh recognition cycle immediately instead of waiting for that 60-second
  interval.
- It avoids restarting the same song when a later recognition confirms it.
- The status card always shows whether CoffeeSync is recording, recognizing,
  switching playback, or the live countdown until its next recognition cycle.
- **Re-sync** immediately starts a new recognition cycle and allows the
  recognised song to be aligned again without waiting for the normal cadence.
- The packaged app does not retain microphone WAV clips or recognition logs.

## Experimental YouTube Music resolver

CoffeeSync keeps the same visible official YouTube IFrame player but resolves a
recognised title and artist through
`ytmusicapi` with the YouTube Music `songs` filter first. This is intended to
avoid selecting concert, cover, karaoke, or remix videos that happen to share a
title. `ytmusicapi` is an unofficial library that emulates YouTube Music web
requests; it is not endorsed by Google and may break if the service changes.

## Build and package

Requirements: macOS, Xcode command-line tools, and the repository including
`CoffeeSync/DevelopmentSupport/ShazamIO`.

```sh
make test
make package
```

`make package` builds a native Release app without Apple-only capabilities,
sanitizes the bundled Python runtime, strips local debug symbols, ad-hoc signs
it, and writes these artifacts to `dist/`:

```text
CoffeeSync-<version>.dmg
SHA256SUMS
```

Override the version when preparing a release:

```sh
VERSION=1.1.0 make package
```

The checked-in runtime is purpose-built for recognition and catalog resolution:
it excludes `pip`, developer entry points, tests, bytecode caches, and local
paths in text build metadata. The release packaging step additionally strips
debug symbols from native binaries. Run the same scripted cleanup again after
changing runtime dependencies:

```sh
scripts/sanitize-shazam-runtime.py CoffeeSync/DevelopmentSupport/ShazamIO/python
```

## Limitations and responsible use

Recognition and sync quality depend on room noise, track version, network
latency, YouTube availability, and player buffering. A recognised song may map
to a cover, live version, remix, or a different upload. YouTube controls
availability, embeddability, API quotas, regions, and playback behavior.

CoffeeSync is a personal hobby / holiday project. It is not affiliated with
Apple, Shazam, Google, YouTube, or any café or rights holder. The bundled
ShazamIO integration is an unofficial client of an Shazam endpoint, not an
Apple/Shazam SDK; its behavior and permission to use may change. Do not use
CoffeeSync, ShazamIO, or captured recordings commercially, as a public service,
or in ways that violate platform terms, copyright, privacy, or recording laws.
Third-party notices are included in
[`CoffeeSync/DevelopmentSupport/ShazamIO/THIRD_PARTY_NOTICES.md`](CoffeeSync/DevelopmentSupport/ShazamIO/THIRD_PARTY_NOTICES.md).
