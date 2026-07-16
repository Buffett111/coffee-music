import Foundation

enum YouTubePlaybackError: LocalizedError {
    case musicCatalogUnavailable(String)
    case noCanonicalSong
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .musicCatalogUnavailable(detail):
            "YouTube Music 曲庫解析無法使用：\(detail)"
        case .noCanonicalSong:
            "YouTube Music 找不到可播放的標準歌曲版本。"
        case .invalidResponse:
            "YouTube Music 回傳了無法讀取的歌曲資料。"
        }
    }
}

struct YouTubePlaybackTarget: Equatable, Sendable {
    let videoID: String
    let videoTitle: String
    let channelTitle: String
    let startOffset: TimeInterval
}

struct YouTubeMusicSongCandidate: Decodable, Equatable, Sendable {
    let videoID: String
    let title: String
    let artists: [String]
    let album: String?
    let durationSeconds: TimeInterval?
    let resultType: String?
}

/// Uses YouTube Music's song-only catalog as a resolver, then hands its video
/// ID to YouTube's official, visible IFrame player. The resolver is provided by
/// the bundled `ytmusicapi` experimental dependency and is intentionally kept
/// separate from playback.
final class YouTubePlaybackEngine {
    private let musicCatalog = YouTubeMusicCatalogResolver()

    func resolve(
        song: RecognizedSong,
        startOffset: TimeInterval
    ) async throws -> YouTubePlaybackTarget {
        let winner = try await musicCatalog.resolve(song: song)
        return YouTubePlaybackTarget(
            videoID: winner.videoID,
            videoTitle: winner.title,
            channelTitle: winner.artists.joined(separator: ", "),
            startOffset: max(0, startOffset)
        )
    }

    static func bestCandidate(
        in candidates: [YouTubeMusicSongCandidate],
        for song: RecognizedSong
    ) -> YouTubeMusicSongCandidate? {
        candidates.max { score($0, for: song) < score($1, for: song) }
    }

    private static func score(_ candidate: YouTubeMusicSongCandidate, for song: RecognizedSong) -> Int {
        let expectedTitle = normalized(song.title)
        let expectedArtist = normalized(song.artist)
        let title = normalized(candidate.title)
        let artists = candidate.artists.map(normalized)
        let sourceDescription = "\(expectedTitle) \(expectedArtist)"
        var result = 0

        if title == expectedTitle { result += 100 }
        else if title.contains(expectedTitle) { result += 25 }
        else { result -= 80 }

        if artists.contains(expectedArtist) { result += 60 }
        else if artists.contains(where: { $0.contains(expectedArtist) || expectedArtist.contains($0) }) { result += 20 }
        else { result -= 100 }

        let candidateDescription = "\(title) \(normalized(candidate.album ?? ""))"
        for marker in variantMarkers where candidateDescription.contains(marker) && !sourceDescription.contains(marker) {
            result -= 45
        }
        if candidate.durationSeconds == nil { result -= 5 }
        return result
    }

    private static let variantMarkers = [
        "live", "concert", "cover", "karaoke", "remix", "acoustic",
        "instrumental", "spedup", "slowed", "nightcore", "version",
        "tribute", "piano", "guitar"
    ]

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

private final class YouTubeMusicCatalogResolver {
    struct Environment: Sendable {
        let python: URL
        let script: URL

        static func bundledRuntime() -> Environment {
            let root = Bundle(for: YouTubePlaybackEngine.self).resourceURL?
                .appendingPathComponent("ShazamIO", isDirectory: true)
                ?? URL(fileURLWithPath: "/ShazamIO-runtime-missing", isDirectory: true)
            return Environment(
                python: root.appendingPathComponent("python/bin/python3.10", isDirectory: false),
                script: root.appendingPathComponent("resolve_youtube_music.py", isDirectory: false)
            )
        }
    }

    private let environment: Environment

    init(environment: Environment = .bundledRuntime()) {
        self.environment = environment
    }

    func resolve(song: RecognizedSong) async throws -> YouTubeMusicSongCandidate {
        guard FileManager.default.isExecutableFile(atPath: environment.python.path),
              FileManager.default.fileExists(atPath: environment.script.path) else {
            throw YouTubePlaybackError.musicCatalogUnavailable("找不到內嵌的 ytmusicapi runtime。")
        }

        let output = try await run(arguments: [environment.script.path, song.title, song.artist])
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: output.standardOutput)
        } catch {
            throw YouTubePlaybackError.invalidResponse
        }
        guard output.exitCode == 0 else {
            throw YouTubePlaybackError.musicCatalogUnavailable(response.error ?? output.combinedText)
        }
        guard let winner = YouTubePlaybackEngine.bestCandidate(in: response.candidates, for: song) else {
            throw YouTubePlaybackError.noCanonicalSong
        }
        return winner
    }

    private func run(arguments: [String]) async throws -> CatalogProcessOutput {
        try await Task.detached(priority: .userInitiated) { [environment] in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = environment.python
            // The runtime lives inside the signed app bundle. Prevent Python
            // from writing __pycache__ files there during catalog resolution.
            process.arguments = ["-B"] + arguments
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            return CatalogProcessOutput(
                exitCode: process.terminationStatus,
                standardOutput: stdout.fileHandleForReading.readDataToEndOfFile(),
                standardError: stderr.fileHandleForReading.readDataToEndOfFile()
            )
        }.value
    }

    private struct Response: Decodable {
        let candidates: [YouTubeMusicSongCandidate]
        let error: String?
    }
}

private struct CatalogProcessOutput: Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data

    var combinedText: String {
        [standardOutput, standardError]
            .compactMap { String(data: $0, encoding: .utf8) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
