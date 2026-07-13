# CoffeeSync prototype

CoffeeSync is an iPhone-first SwiftUI prototype for the café use case: wear ANC headphones, manually start a coffee session, recognize the song playing in the room, then automatically start the matching Apple Music track at an estimated equivalent point in the song.

## What is implemented

- A manual Coffee Session UI with clear microphone/Apple Music permission states.
- Headphone-route guard: the session does not start through the phone speaker.
- Live microphone capture using `AVAudioEngine` and catalog matching through ShazamKit.
- Automatic Apple Music lookup using the matched Apple Music ID and playback using `ApplicationMusicPlayer`.
- A pure `SyncPlanner` that advances ShazamKit's match offset by processing, output-route, and manually calibrated latency; it also avoids seeking off the end of a song.
- A track-switch gate that prevents repeat matches and short transient detections from repeatedly restarting playback.
- An in-app latency calibration slider, current-match status, and a background-audio declaration for an active session.

## Open in Xcode

Full Xcode is installed on this Mac and the app plus unit-test bundle compile successfully. To launch the app:

1. Open `CoffeeSync.xcodeproj`.
2. In Signing & Capabilities, choose an Apple Developer team and a unique bundle ID.
3. In the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list), enable **ShazamKit** for that App ID. ShazamKit is enabled at the App ID; it does not need a hand-authored entitlement.
4. Add the MusicKit capability if Xcode offers it, then run on a physical iPhone signed in to an Apple Music account with an active playback subscription.
5. Connect ANC headphones, approve microphone and Apple Music access, then tap **開始咖啡工作階段**.

## Local verification

The source and test target compile with Xcode 26.6. An iOS Simulator runtime is required to execute the XCTest suite:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CoffeeSync.xcodeproj -scheme CoffeeSync \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /private/tmp/CoffeeSyncDerivedData test \
  CODE_SIGNING_ALLOWED=NO
```

The unit tests cover timing-offset calculation, end-of-track clamping, duplicate-match suppression, and retrying a failed playback attempt.

## Validation plan

Use a physical iPhone in a café-like setup with known tracks. Record, for each test, recognition time, selected catalog version, initial timing error, and whether a second recognition tried to restart the same song. Acceptance targets for the next iteration are: popular catalog tracks identified within 10 seconds, initial perceived alignment within 1.5 seconds after calibration, and no repeat restarts while the same song remains on.

## Known prototype limits

- `matchOffset` aligns against the catalog version. Live performances, remixes, speed changes, and venue DSP can drift or fail to match.
- The first real-device spike should verify that simultaneous microphone capture and `ApplicationMusicPlayer` keep the desired Bluetooth/AirPods route. The implementation blocks speaker output but does not control an earphone's ANC mode; the wearer enables ANC manually.
- Apple Music availability is storefront and subscription dependent. If ShazamKit cannot provide a playable Apple Music ID, the prototype reports the condition instead of playing a guessed track.
- The app is designed for the user's personal Apple Music playback, never for rebroadcasting café audio.
