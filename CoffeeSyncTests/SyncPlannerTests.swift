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

        XCTAssertEqual(plan.targetOffset, 49.0, accuracy: 0.000_1)
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

    func testPlannerUsesFiveSecondCaptureAsTheInitialOffsetBeforeExtraDelay() {
        let song = RecognizedSong(
            title: "Fresh Brew",
            artist: "Beans",
            musicURL: nil,
            matchOffset: 12,
            receivedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let plan = SyncPlanner(startupAllowance: 0, captureDuration: 5).plan(
            for: song,
            now: Date(timeIntervalSinceReferenceDate: 100),
            outputLatency: 15
        )

        XCTAssertEqual(plan.targetOffset, 32, accuracy: 0.000_1)
        XCTAssertEqual(plan.estimatedDrift, 20, accuracy: 0.000_1)
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

    func testYouTubeSearchPrefersTheTitleAndArtistMatch() {
        let song = RecognizedSong(title: "Wish You The Best", artist: "Lewis Capaldi", musicURL: nil, matchOffset: 12)
        let candidates = [
            YouTubeSearchCandidate(videoID: "wrong", title: "Best of Pop", channelTitle: "Playlist Hub"),
            YouTubeSearchCandidate(videoID: "right", title: "Lewis Capaldi - Wish You The Best (Official Audio)", channelTitle: "Lewis Capaldi")
        ]

        XCTAssertEqual(YouTubePlaybackEngine.bestCandidate(in: candidates, for: song)?.videoID, "right")
    }

    func testShazamIORunnerResponseUsesTitleArtistAndReturnedOffsetForSeeking() throws {
        let response = """
        {
          "input": "/tmp/clip.wav",
          "recognized": true,
          "matchCount": 1,
          "latencyMs": 823,
          "track": {
            "title": "Espresso",
            "subtitle": "Sabrina Carpenter",
            "key": "123"
          },
          "firstMatch": {
            "offset": 21.536,
            "timeSkew": 0.0,
            "frequencySkew": 0.0
          }
        }
        """

        let attempt = try ShazamIORecognitionEngine().decodeRecognition(
            Data(response.utf8),
            attemptID: UUID(),
            recordedAt: .now,
            filename: "clip.wav",
            byteCount: 1_024
        )

        XCTAssertEqual(attempt.diagnostic.provider, .shazamIO)
        XCTAssertEqual(attempt.song?.title, "Espresso")
        XCTAssertEqual(attempt.song?.artist, "Sabrina Carpenter")
        XCTAssertEqual(try XCTUnwrap(attempt.song).matchOffset, 21.536, accuracy: 0.000_1)
    }

    func testShazamIONoMatchPreservesTheRunnerFailureInDiagnostics() throws {
        let response = """
        { "recognized": false, "matchCount": 0, "track": null, "error": "no match" }
        """

        let attempt = try ShazamIORecognitionEngine().decodeRecognition(
            Data(response.utf8),
            attemptID: UUID(),
            recordedAt: .now,
            filename: "clip.wav",
            byteCount: 1_024,
            processExitCode: 2
        )

        XCTAssertNil(attempt.song)
        XCTAssertEqual(attempt.diagnostic.provider, .shazamIO)
        XCTAssertEqual(attempt.diagnostic.errorDescription, "ShazamIO runner 失敗：no match")
    }

    func testShazamIOBundledRuntimeSelfCheckUsesNoNetworkRecognition() async throws {
        let engine = ShazamIORecognitionEngine()
        guard engine.isAvailable() else {
            throw XCTSkip("The standalone shazamio-benchmark repository is not installed on this Mac.")
        }

        switch await engine.selfCheck() {
        case let .success(check):
            XCTAssertEqual(check.status, "ok")
            XCTAssertEqual(check.shazamio, "0.8.1")
            XCTAssertFalse(check.networkRequestMade)
        case let .failure(error):
            XCTFail("Bundled ShazamIO self-check failed: \(error.localizedDescription)")
        }
    }
}
