import Foundation
import XCTest
@testable import CoffeeSync

final class SyncPlannerTests: XCTestCase {
    func testPlannerAdvancesFromMatchedOffsetByObservedAndRouteDelay() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let song = RecognizedSong(
            title: "Roast",
            artist: "Beans",
            musicURL: URL(string: "https://music.apple.com/example"),
            matchOffset: 42,
            receivedAt: receivedAt
        )
        let planner = SyncPlanner(startupAllowance: 0.35)

        let plan = planner.plan(
            for: song,
            now: Date(timeIntervalSinceReferenceDate: 1_001.2),
            outputLatency: 0.45,
            songDuration: 240
        )

        XCTAssertEqual(plan.targetOffset, 44.0, accuracy: 0.000_1)
    }

    func testPlannerDoesNotSeekPastTheUsableEndOfTrack() {
        let song = RecognizedSong(
            title: "Last Sip",
            artist: "Beans",
            musicURL: URL(string: "https://music.apple.com/example"),
            matchOffset: 179.8,
            receivedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let plan = SyncPlanner(startupAllowance: 0.35).plan(
            for: song,
            now: Date(timeIntervalSinceReferenceDate: 11),
            outputLatency: 0.5,
            songDuration: 180
        )

        XCTAssertEqual(plan.targetOffset, 179.5, accuracy: 0.000_1)
    }

    func testGateRejectsTheSameSongAndRapidTrackThrashing() {
        let first = RecognizedSong(title: "One", artist: "Artist", musicURL: URL(string: "https://music.apple.com/one"), matchOffset: 10)
        let second = RecognizedSong(title: "Two", artist: "Artist", musicURL: URL(string: "https://music.apple.com/two"), matchOffset: 10)
        var gate = TrackSwitchGate(minimumSwitchInterval: 8)
        let start = Date(timeIntervalSinceReferenceDate: 10)

        XCTAssertTrue(gate.beginAttempt(for: first, at: start))
        gate.commitAttempt(for: first, at: start)
        XCTAssertFalse(gate.beginAttempt(for: first, at: start.addingTimeInterval(30)))
        XCTAssertFalse(gate.beginAttempt(for: second, at: start.addingTimeInterval(4)))
        XCTAssertTrue(gate.beginAttempt(for: second, at: start.addingTimeInterval(9)))
    }

    func testGateAllowsRetryAfterAFailedPlaybackAttempt() {
        let song = RecognizedSong(title: "Retry", artist: "Artist", musicURL: URL(string: "https://music.apple.com/retry"), matchOffset: 10)
        var gate = TrackSwitchGate()
        let now = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(gate.beginAttempt(for: song, at: now))
        gate.cancelAttempt()
        XCTAssertTrue(gate.beginAttempt(for: song, at: now.addingTimeInterval(1)))
    }

    func testAudDTimecodeSupportsMinuteAndHourFormats() {
        XCTAssertEqual(AudDTimecode.seconds(from: "2:03"), 123, accuracy: 0.000_1)
        XCTAssertEqual(AudDTimecode.seconds(from: "1:02:03"), 3_723, accuracy: 0.000_1)
        XCTAssertEqual(AudDTimecode.seconds(from: nil), 0, accuracy: 0.000_1)
    }

    func testAudDResponseUsesTimecodeAndAppleMusicURL() throws {
        let response = """
        {
          "status": "success",
          "result": {
            "title": "Everybody Wants To Rule The World",
            "artist": "Tears For Fears",
            "timecode": "00:56",
            "apple_music": { "url": "https://music.apple.com/us/album/example?i=123" }
          }
        }
        """

        let song = try AudDRecognitionEngine().decodeRecognition(Data(response.utf8))

        XCTAssertEqual(song.title, "Everybody Wants To Rule The World")
        XCTAssertEqual(song.artist, "Tears For Fears")
        XCTAssertEqual(song.matchOffset, 56, accuracy: 0.000_1)
        XCTAssertEqual(song.musicURL?.host, "music.apple.com")
    }

    func testAudDAttemptRecordsMissingTokenWithoutReadingAudio() async {
        let attemptID = UUID()
        let attempt = await AudDRecognitionEngine().recognize(
            fileAt: URL(fileURLWithPath: "/tmp/does-not-exist.wav"),
            token: " ",
            attemptID: attemptID
        )

        XCTAssertNil(attempt.song)
        XCTAssertEqual(attempt.diagnostic.attemptID, attemptID)
        XCTAssertEqual(attempt.diagnostic.sourceFilename, "does-not-exist.wav")
        XCTAssertEqual(attempt.diagnostic.errorDescription, "請先在設定貼上 AudD API token。")
        XCTAssertNil(attempt.diagnostic.responseExcerpt)
    }

    func testMusicPlayerSnapshotOnlyAllowsSeekForPlayingTrackWithEnoughDuration() {
        XCTAssertTrue(MusicPlayerSnapshot.parse("playing|220.2").canSeek(to: 21.536))
        XCTAssertFalse(MusicPlayerSnapshot.parse("paused|220.2").canSeek(to: 21.536))
        XCTAssertFalse(MusicPlayerSnapshot.parse("playing|20").canSeek(to: 21.536))
        XCTAssertFalse(MusicPlayerSnapshot.parse("unknown|0").canSeek(to: 21.536))
    }

    func testMusicPlayerSnapshotRequiresTheRecognizedSongBeforeSeeking() {
        let song = RecognizedSong(title: "Hold Me While You Wait", artist: "Lewis Capaldi", musicURL: nil, matchOffset: 12)

        XCTAssertTrue(MusicPlayerSnapshot.parse("playing|219|Hold Me While You Wait|Lewis Capaldi").matches(song))
        XCTAssertFalse(MusicPlayerSnapshot.parse("playing|219|AutoPlay|").matches(song))
    }

    func testCatalogFallbackDoesNotClaimPlayback() {
        XCTAssertNotEqual(MusicAppPlaybackResult.catalogOpened, .synchronized)
        XCTAssertNotEqual(MusicAppPlaybackResult.catalogOpened, .playingWithoutSynchronization)
        XCTAssertNotEqual(MusicAppPlaybackResult.targetDidNotStart, .synchronized)
    }
}
