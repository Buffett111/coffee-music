# CoffeeSync for Mac

CoffeeSync is a personal macOS utility for the café use case: it records a short
microphone clip, asks AudD to identify the song playing in the room, then asks
the installed Music.app to play the matching Apple Music track at an estimated
equivalent point in the song. The intent is to enjoy the café's music through
ANC headphones while reducing speech and coffee-machine noise.

## Why this is a Mac app

The archived iPhone implementation relied on ShazamKit and MusicKit App
Services. Those services require Apple Developer Program access even when the
app is for personal use. This macOS implementation avoids both frameworks:

- **Recognition:** AudD's documented REST API, using a fresh 10-second WAV
  clip from the Mac microphone.
- **Playback:** macOS Automation controls the user's installed Music.app. It
  searches the user's synced library first, then falls back to AudD's Apple
  Music link and seeks to the detected time.
- **Credentials:** the AudD token lives in the local macOS Keychain, never in
  source control or an Info.plist.

The previous iOS prototype is retained in Git as the `ios-prototype` tag.

## Setup and run

1. Create an AudD account and copy an API token from its dashboard. The AudD
   documentation describes the request format and its current trial/usage
   terms: <https://docs.audd.io/>.
2. Open `CoffeeSync.xcodeproj` in Xcode and choose the **CoffeeSync** scheme
   with **My Mac** as the destination.
3. Run the app. Paste the token in **AudD 連線設定** and select
   **儲存至 Keychain**.
4. Click **開始咖啡工作階段** and approve:
   - Microphone access for CoffeeSync.
   - Automation access when macOS asks whether CoffeeSync may control Music.
5. Use the Mac's built-in microphone to hear the room and route Music.app to
   your ANC headphones. Keeping AirPods as output-only avoids the Bluetooth
   hands-free profile's lower audio quality.

For a command-line build that does not require an Apple Developer Program
membership:

```sh
xcodebuild -project CoffeeSync.xcodeproj -scheme CoffeeSync \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/CoffeeSyncDerivedData-macOS \
  build CODE_SIGNING_ALLOWED=NO
```

## How a session works

1. Record ten seconds of ambient audio.
2. Upload the temporary WAV clip to AudD.
3. Read the title, artist, Apple Music URL, and match timecode returned by
   AudD.
4. Add elapsed processing time plus the user-calibrated output allowance.
5. Ask Music.app to play and seek. The app rechecks roughly every 45 seconds,
   avoids restarting a stable match, and deletes every temporary WAV clip once
   AudD returns.

## Limits and privacy

- AudD is an external recognition service: every active recognition cycle
  uploads a short audio clip. CoffeeSync does not retain clips after the
  request finishes.
- This app does not control an earphone's ANC mode; enable ANC on your own
  headphones.
- Song matching and offset alignment remain approximate. Remixes, live
  versions, heavy room noise, and delayed Music.app page loading can drift or
  fail.
- Music.app must be signed in to an Apple Music account able to play the
  matched track. The app can build and run for your own Mac without App Store
  distribution or Developer Program enrollment.
