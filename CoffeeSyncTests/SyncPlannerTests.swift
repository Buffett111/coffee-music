import Foundation
import XCTest
@testable import CoffeeSync

final class SyncPlannerTests: XCTestCase {
    func testPlannerAdvancesFromMatchByCaptureAndConfiguredDelay() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let song = RecognizedSong(title: "Roast", artist: "Beans", matchOffset: 42, receivedAt: receivedAt)
        let planner = SyncPlanner(startupAllowance: 0.35, captureDuration: 5)

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

    func testCaptureDurationOptionsExposeFiveEightAndTenSeconds() {
        XCTAssertEqual(CaptureDurationOption.allCases.map(\.seconds), [5, 8, 10])
        XCTAssertEqual(CaptureDurationOption.eight.displayName, "8 秒")
    }

    func testGateRejectsTheSameSongAndRapidTrackThrashing() {
        let first = RecognizedSong(title: "One", artist: "Artist", matchOffset: 10)
        let second = RecognizedSong(title: "Two", artist: "Artist", matchOffset: 10)
        var gate = TrackSwitchGate(minimumSwitchInterval: 8)
        let start = Date(timeIntervalSinceReferenceDate: 10)

        XCTAssertTrue(gate.beginAttempt(for: first, at: start))
        gate.commitAttempt(for: first, at: start)
        XCTAssertFalse(gate.beginAttempt(for: first, at: start.addingTimeInterval(30)))
        XCTAssertFalse(gate.beginAttempt(for: second, at: start.addingTimeInterval(4)))
        XCTAssertTrue(gate.beginAttempt(for: second, at: start.addingTimeInterval(9)))
    }

    func testYouTubeSearchPrefersTheTitleAndArtistMatch() {
        let song = RecognizedSong(title: "Wish You The Best", artist: "Lewis Capaldi", matchOffset: 12)
        let candidates = [
            YouTubeSearchCandidate(videoID: "wrong", title: "Best of Pop", channelTitle: "Playlist Hub"),
            YouTubeSearchCandidate(videoID: "right", title: "Lewis Capaldi - Wish You The Best (Official Audio)", channelTitle: "Lewis Capaldi")
        ]

        XCTAssertEqual(YouTubePlaybackEngine.bestCandidate(in: candidates, for: song)?.videoID, "right")
    }

    func testShazamIORunnerResponseUsesReturnedOffsetForSeeking() throws {
        let response = """
        {
          "recognized": true,
          "track": { "title": "Espresso", "subtitle": "Sabrina Carpenter", "key": "123" },
          "firstMatch": { "offset": 21.536, "timeSkew": 0.0, "frequencySkew": 0.0 }
        }
        """
        let attempt = try ShazamIORecognitionEngine().decodeRecognition(
            Data(response.utf8), attemptID: UUID(), recordedAt: .now, filename: "clip.wav", byteCount: 1_024
        )

        XCTAssertEqual(attempt.diagnostic.provider, "ShazamIO")
        XCTAssertEqual(attempt.song?.title, "Espresso")
        XCTAssertEqual(try XCTUnwrap(attempt.song).matchOffset, 21.536, accuracy: 0.000_1)
    }

    func testShazamIOBundledRuntimeSelfCheckUsesNoNetworkRecognition() async throws {
        let engine = ShazamIORecognitionEngine()
        guard engine.isAvailable() else { throw XCTSkip("Bundled ShazamIO runtime is unavailable.") }
        switch await engine.selfCheck() {
        case let .success(check):
            XCTAssertEqual(check.status, "ok")
            XCTAssertFalse(check.networkRequestMade)
        case let .failure(error):
            XCTFail("Bundled ShazamIO self-check failed: \(error.localizedDescription)")
        }
    }
}
