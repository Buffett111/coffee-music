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

/// Uses macOS Automation to control the user's installed Music.app.
/// No MusicKit developer token is needed; macOS asks the user for Automation access.
final class MusicAppPlaybackEngine {
    func play(_ song: RecognizedSong, from offset: TimeInterval) throws {
        let query = escape(song.displayName)
        let seek = String(format: "%.3f", max(0, offset))

        let libraryScript = """
        tell application "Music"
            set matches to (search library playlist 1 for "\(query)" only all)
            if (count of matches) > 0 then
                play item 1 of matches
                delay 0.8
                set player position to \(seek)
                return "library"
            end if
        end tell
        return "not found"
        """

        if try execute(libraryScript) == "library" {
            return
        }

        guard let url = song.musicURL else { throw MusicAppPlaybackError.missingMusicLink }
        let urlString = escape(url.absoluteString)
        let catalogScript = """
        tell application "Music"
            activate
            open location "\(urlString)"
            delay 2
            play
            set player position to \(seek)
        end tell
        """
        _ = try execute(catalogScript)
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

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
