import AppKit
import Foundation

enum MusicAppPlaybackError: LocalizedError {
    case missingMusicLink
    case automationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingMusicLink:
            "AudD 沒有回傳 Apple Music 連結，無法自動播放這一首。"
        case let .automationFailed(message):
            "無法控制 Music.app：\(message)"
        }
    }
}

enum MusicAppPlaybackResult: Equatable {
    case synchronized
    case playingWithoutSynchronization
}

struct MusicPlayerSnapshot: Equatable {
    let state: String
    let duration: TimeInterval

    var isPlaying: Bool { state.lowercased() == "playing" }

    func canSeek(to offset: TimeInterval) -> Bool {
        isPlaying && duration.isFinite && duration > offset
    }

    static func parse(_ value: String) -> MusicPlayerSnapshot {
        let fields = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let state = fields.first.map(String.init) ?? "unknown"
        let duration = fields.count == 2 ? TimeInterval(fields[1]) ?? 0 : 0
        return MusicPlayerSnapshot(state: state, duration: duration)
    }
}

/// Uses macOS Automation to control the user's installed Music.app.
/// No MusicKit developer token is needed; macOS asks the user for Automation access.
final class MusicAppPlaybackEngine {
    private let readinessAttempts = 20
    private let readinessInterval: Duration = .milliseconds(500)

    func play(_ song: RecognizedSong, from offset: TimeInterval) async throws -> MusicAppPlaybackResult {
        let query = escape(song.displayName)

        let libraryScript = """
        tell application "Music"
            set matches to (search library playlist 1 for "\(query)" only all)
            if (count of matches) > 0 then
                play item 1 of matches
                return "library"
            end if
        end tell
        return "not found"
        """

        if try execute(libraryScript) == "library" {
            return try await waitForSeekReadiness(offset: offset)
        }

        guard let url = song.musicURL else { throw MusicAppPlaybackError.missingMusicLink }
        let urlString = escape(url.absoluteString)
        let catalogScript = """
        tell application "Music"
            activate
            open location "\(urlString)"
            play
            return "catalog"
        end tell
        """
        _ = try execute(catalogScript)
        return try await waitForSeekReadiness(offset: offset)
    }

    func stop() {
        _ = try? execute("tell application \"Music\" to stop")
    }

    private func execute(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw MusicAppPlaybackError.automationFailed("無法建立 AppleScript。")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "未知 Automation 錯誤。"
            throw MusicAppPlaybackError.automationFailed(message)
        }
        return result.stringValue ?? ""
    }

    private func waitForSeekReadiness(offset: TimeInterval) async throws -> MusicAppPlaybackResult {
        let safeOffset = max(0, offset)
        for attempt in 0 ..< readinessAttempts {
            if try playerSnapshot().canSeek(to: safeOffset) {
                do {
                    try setPlayerPosition(safeOffset)
                    return .synchronized
                } catch {
                    // Music can report a playable current track a fraction before
                    // its stream is actually seekable. Poll again instead of
                    // failing the recognition cycle.
                }
            }

            if attempt < readinessAttempts - 1 {
                try await Task.sleep(for: readinessInterval)
            }
        }
        return .playingWithoutSynchronization
    }

    private func playerSnapshot() throws -> MusicPlayerSnapshot {
        let script = """
        tell application "Music"
            try
                return (player state as text) & "|" & (duration of current track as text)
            on error
                return "unknown|0"
            end try
        end tell
        """
        return MusicPlayerSnapshot.parse(try execute(script))
    }

    private func setPlayerPosition(_ offset: TimeInterval) throws {
        let seek = String(format: "%.3f", offset)
        _ = try execute("tell application \"Music\" to set player position to \(seek)")
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
