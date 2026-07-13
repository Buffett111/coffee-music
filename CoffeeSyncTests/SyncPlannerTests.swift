import Foundation
import XCTest
@testable import CoffeeSync

final class SyncPlannerTests: XCTestCase {
    func testPlannerAdvancesFromMatchedOffsetByObservedAndRouteDelay() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let song = RecognizedSong(
            title: "Roast",
            artist: "Beans",
            appleMusicID: "i.example",
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
            appleMusicID: "i.example",
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
        let first = RecognizedSong(title: "One", artist: "Artist", appleMusicID: "i.one", matchOffset: 10)
        let second = RecognizedSong(title: "Two", artist: "Artist", appleMusicID: "i.two", matchOffset: 10)
        var gate = TrackSwitchGate(minimumSwitchInterval: 8)
        let start = Date(timeIntervalSinceReferenceDate: 10)

        XCTAssertTrue(gate.beginAttempt(for: first, at: start))
        gate.commitAttempt(for: first, at: start)
        XCTAssertFalse(gate.beginAttempt(for: first, at: start.addingTimeInterval(30)))
        XCTAssertFalse(gate.beginAttempt(for: second, at: start.addingTimeInterval(4)))
        XCTAssertTrue(gate.beginAttempt(for: second, at: start.addingTimeInterval(9)))
    }

    func testGateAllowsRetryAfterAFailedPlaybackAttempt() {
        let song = RecognizedSong(title: "Retry", artist: "Artist", appleMusicID: "i.retry", matchOffset: 10)
        var gate = TrackSwitchGate()
        let now = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(gate.beginAttempt(for: song, at: now))
        gate.cancelAttempt()
        XCTAssertTrue(gate.beginAttempt(for: song, at: now.addingTimeInterval(1)))
    }
}
