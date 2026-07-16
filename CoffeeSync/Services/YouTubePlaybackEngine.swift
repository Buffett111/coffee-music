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
    let searchRank: Int

    init(
        videoID: String,
        title: String,
        artists: [String],
        album: String?,
        durationSeconds: TimeInterval?,
        resultType: String?,
        searchRank: Int = 0
    ) {
        self.videoID = videoID
        self.title = title
        self.artists = artists
        self.album = album
        self.durationSeconds = durationSeconds
        self.resultType = resultType
        self.searchRank = searchRank
    }
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
        // A title match alone is unsafe: songs with the same English title are
        // common. Never use a candidate whose artist set has no local match.
        let eligible = candidates.filter { artistMatch($0.artists, expected: song.artist) != .none }
        guard !eligible.isEmpty else { return nil }

        return eligible.max { lhs, rhs in
            let leftScore = score(lhs, for: song)
            let rightScore = score(rhs, for: song)
            if leftScore == rightScore {
                // Keep YouTube Music's relevance order when local evidence is
                // tied. Lower rank means the service returned it earlier.
                return lhs.searchRank > rhs.searchRank
            }
            return leftScore < rightScore
        }
    }

    private static func score(_ candidate: YouTubeMusicSongCandidate, for song: RecognizedSong) -> Int {
        let expectedTitle = normalized(song.title)
        let title = normalized(candidate.title)
        let matchedArtists = artistMatch(candidate.artists, expected: song.artist)
        let sourceDescription = "\(expectedTitle) \(normalized(song.artist))"
        // Search rank is intentionally a modest signal: a lower-ranked item
        // can still win with stronger title/artist evidence, but an exact
        // title from an unrelated artist cannot.
        var result = max(0, 90 - (candidate.searchRank * 9))

        if title == expectedTitle { result += 130 }
        else if title.contains(expectedTitle) || expectedTitle.contains(title) { result += 35 }

        switch matchedArtists {
        case .full: result += 360
        case .partial: result += 150
        case .none: return Int.min
        }

        let candidateDescription = "\(title) \(normalized(candidate.album ?? ""))"
        for marker in variantMarkers where candidateDescription.contains(marker) && !sourceDescription.contains(marker) {
            result -= 45
        }
        if candidate.durationSeconds == nil { result -= 5 }
        return result
    }

    private enum ArtistMatch {
        case none
        case partial
        case full
    }

    private static func artistMatch(_ candidateArtists: [String], expected rawExpectedArtist: String) -> ArtistMatch {
        let expectedArtists = splitArtists(rawExpectedArtist)
        let candidateAliases = Set(candidateArtists.flatMap(artistAliases))
        let matchedCount = expectedArtists.reduce(into: 0) { count, artist in
            if !Set(artistAliases(artist)).isDisjoint(with: candidateAliases) {
                count += 1
            }
        }
        guard matchedCount > 0 else { return .none }
        return matchedCount == expectedArtists.count ? .full : .partial
    }

    private static func splitArtists(_ artists: String) -> [String] {
        let separators = CharacterSet(charactersIn: "&,/;、，")
        let normalizedSeparators = artists
            .replacingOccurrences(of: " feat. ", with: " & ", options: .caseInsensitive)
            .replacingOccurrences(of: " featuring ", with: " & ", options: .caseInsensitive)
            .replacingOccurrences(of: " and ", with: " & ", options: .caseInsensitive)
            .replacingOccurrences(of: "與", with: "&")
            .replacingOccurrences(of: "和", with: "&")
        let parts = normalizedSeparators.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [artists] : parts
    }

    private static func artistAliases(_ artist: String) -> [String] {
        let direct = normalized(artist)
        let latin = normalized(artist.applyingTransform(.toLatin, reverse: false) ?? artist)
        var aliases = Set([direct, latin])
        for group in artistAliasGroups where !aliases.isDisjoint(with: group) {
            aliases.formUnion(group)
        }
        return Array(aliases)
    }

    // Stage names are not reliably derivable by transliteration alone. Keep a
    // small, auditable local alias table for common Chinese/English names; the
    // generic Latin transform above covers ordinary transliterated names.
    private static let artistAliasGroups: [Set<String>] = [
        ["jaychou", "周杰倫", "周杰伦", "zhoujielun"].map(normalized).reduce(into: Set<String>()) { $0.insert($1) },
        ["garyyang", "楊瑞代", "杨瑞代", "yangruida"].map(normalized).reduce(into: Set<String>()) { $0.insert($1) }
    ]

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
