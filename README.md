# CoffeeSync for macOS

CoffeeSync is a macOS hobby project that identifies music playing in a café and
starts a matching, visible YouTube embed near the corresponding point in the
track. It is intended for personal experiments with headphones: keep the venue's
music while reducing surrounding conversation and machine noise.

> **Personal, non-commercial project.** CoffeeSync is a holiday-project / hobby
> experiment. It is not affiliated with Apple, Shazam, Google, YouTube, AudD, or
> any café or music-rights holder. Do not use this project, its bundled ShazamIO
> integration, or collected recordings for commercial purposes, public service
> operation, redistribution as a recognition product, or any activity that
> violates applicable platform terms, copyright, privacy, or music-licensing
> requirements. See [Use and ShazamIO disclaimer](#use-and-shazamio-disclaimer).

## What it does

- Captures a short ambient WAV clip from the Mac's built-in microphone.
- Lets a developer choose a **5, 8, or 10 second** capture window.
- Identifies a track with either **AudD** or the bundled **ShazamIO development
  baseline**.
- Includes an A/B comparison mode that sends the *same WAV* to both recognizers.
- Searches the official YouTube Data API v3 for an embeddable video and plays it
  in a visible WebKit YouTube IFrame Player.
- Estimates the playback position from the recognizer's match offset, capture
  duration, request time, and a developer-adjustable output delay.
- Stores keys in the macOS Keychain and can retain local diagnostic WAV/JSON
  pairs while development diagnostics are enabled.

CoffeeSync does **not** control headphone ANC, reproduce a venue's audio feed,
or guarantee an exact recording/video match.

## Architecture

```text
Mac built-in microphone
        |
        v
AudioClipRecorder  -- selected 5 / 8 / 10 s WAV --> Recognition provider
                                                        |       |
                                                        |       +-- AudD API
                                                        |
                                                        +-- Bundled ShazamIO baseline
        |                                                        |
        +-------------------- recognised title / artist / offset +
                                                                 |
                                                                 v
             SyncPlanner --> YouTube Data API v3 --> WebKit YouTube IFrame Player
```

The selected capture duration is part of the position calculation. For example,
a ShazamIO offset is advanced by the 10-second capture window (when selected),
the time spent recognizing/searching, and the configurable extra delay before
the YouTube player starts.

## Recognition modes

| Mode | Requirements | Playback behavior | Intended use |
| --- | --- | --- | --- |
| **AudD** | AudD API token + YouTube API key | Searches and plays YouTube | Alternative recognition provider |
| **ShazamIO development baseline** | Bundled runtime + YouTube API key | Searches and plays YouTube using the returned fingerprint offset | Local accuracy and integration experiments |
| **Comparison** | AudD API token + bundled runtime | No automatic playback | Fair A/B testing on one identical WAV |

For ShazamIO, **10 seconds** is the recommended starting point: its native
recognizer is designed around that window. Five and eight seconds are exposed
for latency/accuracy experiments, not as an accuracy guarantee.

## Requirements

- macOS on Apple silicon
- Xcode (current macOS SDK) for building and running the app
- Microphone permission
- A [YouTube Data API v3](https://developers.google.com/youtube/v3/getting-started)
  API key for all modes that play YouTube
- An [AudD](https://docs.audd.io/) API token only when using AudD or comparison
  mode

The ShazamIO baseline is bundled under
`CoffeeSync/DevelopmentSupport/ShazamIO`; it does not require a separate Python
installation or an external benchmark repository.

## Quick start

1. Clone the repository and open `CoffeeSync.xcodeproj` in Xcode.
2. Select the **CoffeeSync** scheme and **My Mac** destination.
3. Run the app and approve microphone access.
4. Create a Google Cloud project, enable **YouTube Data API v3**, and create an
   API key. Paste it into CoffeeSync and choose **Save to Keychain**.
5. Choose a recognition mode:
   - For **ShazamIO development baseline**, no recognition key is required.
   - For **AudD** or **Comparison**, add and save an AudD API token as well.
6. Select a capture duration. Start with **10 seconds** for ShazamIO.
7. Start a session. Use the Mac's built-in microphone for room audio; route Mac
   output to headphones if desired.

Before recording, use **Test bundled ShazamIO baseline** to confirm that the
embedded Python runtime can start. It performs no microphone capture and sends
no recognition request. Use **Test YouTube playback** to check only the YouTube
search/player path.

## Build and test from the command line

The project can be built locally without Apple Developer Program membership:

```sh
xcodebuild -project CoffeeSync.xcodeproj -scheme CoffeeSync \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/CoffeeSyncDerivedData-macOS \
  build CODE_SIGNING_ALLOWED=NO
```

Run the unit tests with:

```sh
xcodebuild -project CoffeeSync.xcodeproj -scheme CoffeeSync \
  -configuration Debug \
  -derivedDataPath /private/tmp/CoffeeSyncDerivedData-macOS \
  test CODE_SIGNING_ALLOWED=NO
```

## Diagnostics and privacy

Development diagnostics are enabled by default. When enabled, CoffeeSync retains
the latest 25 WAV clips and matching JSON records at:

```text
~/Library/Application Support/CoffeeSync/Recognition Diagnostics/
```

Each JSON record includes provider status, clip size, a truncated service
response, and app-side errors. API tokens are deliberately excluded. WAV files
can contain voices and other personal data from a shared space: keep them local,
review them before sharing, and turn diagnostics off when they are no longer
needed.

Recognition necessarily sends the selected clip to the active provider:

- **AudD mode:** sends the clip to AudD.
- **ShazamIO mode:** sends the clip through ShazamIO's undocumented endpoint
  integration.
- **Comparison mode:** sends that same clip to both providers.

Do not record people without an appropriate legal basis or use the app where
recording is prohibited.

## Limitations

- Recognition quality depends on room noise, volume, recording route, track
  version, and the selected capture length.
- A recognizer result and a YouTube result may refer to different versions of a
  song (for example, a live version, remix, cover, or upload with an inaccurate
  title).
- Position alignment is an estimate. Network latency, YouTube startup time, and
  player buffering can create drift; CoffeeSync exposes an additional 0–15
  second delay for calibration.
- YouTube availability, embeddability, API quotas, and regional restrictions are
  controlled by YouTube and may change.
- This project uses standard YouTube video search and the visible IFrame Player;
  it does not use unofficial YouTube Music APIs or automate a YouTube Music
  subscription.

## Use and ShazamIO disclaimer

The ShazamIO integration exists only as a **local development baseline** for
recognition-quality comparison. ShazamIO is an unofficial client that communicates
with an undocumented Shazam endpoint; it is not an Apple, Shazam, or MusicKit
API. Its availability, behavior, and permission to use may change without
notice. Do not represent CoffeeSync as Shazam-compatible, endorsed, certified,
or production-ready.

This repository is provided for personal learning and private experimentation
only. No permission is granted for commercial use. Developers are responsible
for obtaining any necessary permission from API providers and rights holders and
for complying with applicable laws, terms of service, privacy obligations, and
licenses. In particular, the included third-party components retain their own
licenses and notices; see
[`CoffeeSync/DevelopmentSupport/ShazamIO/THIRD_PARTY_NOTICES.md`](CoffeeSync/DevelopmentSupport/ShazamIO/THIRD_PARTY_NOTICES.md).

## Project layout

```text
CoffeeSync/
├── App/                    SwiftUI interface and session orchestration
├── Core/                   Recognition models and synchronization planner
├── Services/               Audio capture, recognition, diagnostics, Keychain, YouTube
├── DevelopmentSupport/
│   └── ShazamIO/           Bundled development-only Python/ShazamIO runtime
└── Resources/              App configuration
CoffeeSyncTests/            Unit tests
```
