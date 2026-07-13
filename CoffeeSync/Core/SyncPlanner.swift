import Foundation

/// Converts a ShazamKit match into the point that Apple Music should play now.
///
/// A match offset refers to the catalog recording.  By the time the app receives
/// that result and asks Apple Music to start, the café track has advanced.  This
/// planner adds the measured elapsed time and a user-calibrated output allowance.
struct SyncPlanner: Sendable {
    var startupAllowance: TimeInterval = 0.35
    var maximumSeekableTail: TimeInterval = 0.5

    func plan(
        for song: RecognizedSong,
        now: Date = .now,
        outputLatency: TimeInterval,
        songDuration: TimeInterval? = nil
    ) -> PlaybackPlan {
        let elapsedSinceMatch = max(0, now.timeIntervalSince(song.receivedAt))
        var offset = max(0, song.matchOffset + elapsedSinceMatch + outputLatency + startupAllowance)

        if let songDuration, songDuration > maximumSeekableTail {
            offset = min(offset, songDuration - maximumSeekableTail)
        }

        return PlaybackPlan(
            targetOffset: offset,
            estimatedDrift: elapsedSinceMatch + outputLatency + startupAllowance,
            explanation: "Match \(format(song.matchOffset)) + elapsed \(format(elapsedSinceMatch)) + route \(format(outputLatency))"
        )
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}

/// Avoids restarting the same song whenever ShazamKit reports the same match.
struct TrackSwitchGate: Sendable {
    var minimumSwitchInterval: TimeInterval = 8
    private(set) var currentIdentity: String?
    private(set) var lastSwitchAt: Date?
    private(set) var pendingIdentity: String?

    mutating func beginAttempt(for song: RecognizedSong, at now: Date = .now) -> Bool {
        guard currentIdentity != song.stableIdentity, pendingIdentity != song.stableIdentity else { return false }
        if let lastSwitchAt, now.timeIntervalSince(lastSwitchAt) < minimumSwitchInterval {
            return false
        }
        pendingIdentity = song.stableIdentity
        return true
    }

    mutating func commitAttempt(for song: RecognizedSong, at now: Date = .now) {
        currentIdentity = song.stableIdentity
        lastSwitchAt = now
        pendingIdentity = nil
    }

    mutating func cancelAttempt() {
        pendingIdentity = nil
    }

    mutating func reset() {
        currentIdentity = nil
        lastSwitchAt = nil
        pendingIdentity = nil
    }
}
