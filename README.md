# CoffeeSync for Mac

CoffeeSync is a personal macOS utility for the café use case: it records a short
microphone clip, asks AudD to identify the song playing in the room, searches
YouTube for a playable match, then starts a visible embedded player at an
estimated equivalent point in the song. The intent is to enjoy the café's music
through ANC headphones while reducing speech and coffee-machine noise.

## Why this is a Mac app

The archived iPhone implementation relied on ShazamKit and MusicKit App
Services. Those services require Apple Developer Program access even when the
app is for personal use. This macOS implementation avoids both frameworks:

- **Recognition:** AudD's documented REST API, using a fresh 5-second WAV
  clip from the Mac microphone.
- **Playback:** the official YouTube Data API v3 searches for an embeddable
  video, then the official YouTube IFrame Player API plays it in-app from the
  detected time.
- **Credentials:** the AudD token and YouTube Data API key live in the local
  macOS Keychain, never in source control or an Info.plist.

The previous iOS prototype is retained in Git as the `ios-prototype` tag.

## Setup and run

1. Create an AudD account and copy an API token from its dashboard. The AudD
   documentation describes the request format and its current trial/usage
   terms: <https://docs.audd.io/>.
2. Create a Google Cloud project, enable **YouTube Data API v3**, then create
   an API key. Google documents the required project and API setup:
   <https://developers.google.com/youtube/v3/getting-started>.
3. Open `CoffeeSync.xcodeproj` in Xcode and choose the **CoffeeSync** scheme
   with **My Mac** as the destination.
4. Run the app. Paste both keys in their corresponding fields and select
   **儲存至 Keychain** for each.
5. Click **開始咖啡工作階段** and approve microphone access for CoffeeSync.
6. For recognition troubleshooting, keep **開發診斷：保留每輪 WAV 與辨識 log**
   enabled and select **開啟診斷資料夾** after a failed attempt.
7. Use the Mac's built-in microphone to hear the room and route the Mac's audio
   to your ANC headphones. Keeping AirPods as output-only avoids the Bluetooth
   hands-free profile's lower audio quality.

## ShazamIO development baseline

The `codex/shazamio-dev-baseline` branch adds a **ShazamIO（開發基線）**
provider and a **雙重比較（同一段 WAV）** mode. This development branch vendors
a portable Python 3.10 runtime, ShazamIO 0.8.1, and shazamio-core 1.1.2 under
`CoffeeSync/DevelopmentSupport/ShazamIO`, then copies that folder into the app
bundle as a resource. It does not require `~/Documents/shazamio-benchmark`.

1. In CoffeeSync, select **ShazamIO（開發基線）**, then choose
   **驗證內嵌 ShazamIO 基線**. This starts the bundled runner but does not
   request microphone access, send audio, or contact the recognition service.
2. For a fair A/B test, select **雙重比較（同一段 WAV）**. CoffeeSync records one
   clip, passes that exact file to both AudD and ShazamIO, displays the two
   title/artist outcomes, and writes one diagnostic JSON log per provider.
   Comparison mode intentionally does not auto-play YouTube, so it needs no
   YouTube API key.

ShazamIO is an unofficial client of an undocumented Shazam endpoint. This
branch is for private, development-only accuracy comparison and must not be
treated as a production recognition integration. The ShazamIO fingerprint offset
is passed to the YouTube seek path when ShazamIO is selected alone; comparison
mode does not auto-play so it can report a clean A/B result.

For a command-line build that does not require an Apple Developer Program
membership:

```sh
xcodebuild -project CoffeeSync.xcodeproj -scheme CoffeeSync \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/CoffeeSyncDerivedData-macOS \
  build CODE_SIGNING_ALLOWED=NO
```

## How a session works

1. Record five seconds of ambient audio.
2. Send the temporary WAV to the selected recognition provider.
3. Read the title, artist, and (when supplied by AudD) match timecode.
4. Add the fixed five-second capture baseline, elapsed processing time, and up
   to 15 seconds of user-calibrated extra output allowance.
5. Search YouTube's official Data API for an embeddable video using the title,
   artist, and `official audio` query, then rank the returned candidates.
6. Load the selected video in a visible IFrame Player and ask it to start from
   the estimated offset. The app rechecks roughly every 45 seconds and avoids
   restarting a stable match.

## Development diagnostics

The diagnostic toggle is enabled by default during development. It retains the
most recent 25 attempts in:

`~/Library/Application Support/CoffeeSync/Recognition Diagnostics/`

Each attempt has a `.wav` recording and a matching `.json` log. The log includes
the provider, clip size, service status, a truncated response, and any app-side
error; it deliberately never includes the API token. These files contain ambient
room audio, so do not upload or share them casually.

## Limits and privacy

- AudD is an external recognition service: every active recognition cycle
  uploads a short audio clip. Development diagnostics retain the most recent
  25 new clips locally while the toggle is on; regular temporary files are
  deleted after each request.
- This app does not control an earphone's ANC mode; enable ANC on your own
  headphones.
- Song matching and offset alignment remain approximate. Remixes, live
  versions, heavy room noise, delayed player startup, and YouTube search
  rankings can drift or choose an unintended version. The selected video title
  and channel are shown before playback for verification.
- YouTube Music does not expose a separate public catalog API for this use
  case. CoffeeSync uses the supported YouTube Data API and visible IFrame
  Player instead; it does not use unofficial cookie-based or reverse-engineered
  YouTube Music APIs. The app can build and run for your own Mac without App
  Store distribution or Apple Developer Program enrollment.
