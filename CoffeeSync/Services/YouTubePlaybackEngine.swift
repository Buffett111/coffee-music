import Foundation
import Security

enum YouTubePlaybackError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case noEmbeddableVideo
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "請先貼上並儲存 YouTube Data API key。"
        case .invalidResponse:
            "YouTube 回傳了無法讀取的搜尋結果。"
        case .noEmbeddableVideo:
            "YouTube 找不到可嵌入播放的對應影片。"
        case let .requestFailed(message):
            "YouTube 搜尋失敗：\(message)"
        }
    }
}

struct YouTubePlaybackTarget: Equatable, Sendable {
    let videoID: String
    let videoTitle: String
    let channelTitle: String
    let startOffset: TimeInterval
}

struct YouTubeSearchCandidate: Equatable, Sendable {
    let videoID: String
    let title: String
    let channelTitle: String
}

/// Official YouTube Data API v3 search followed by the official IFrame player.
/// This intentionally uses standard YouTube video metadata: YouTube Music does
/// not provide a separate public catalog API for third-party macOS apps.
final class YouTubePlaybackEngine {
    func resolve(
        song: RecognizedSong,
        apiKey: String,
        startOffset: TimeInterval
    ) async throws -> YouTubePlaybackTarget {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw YouTubePlaybackError.missingAPIKey }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "5"),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "videoSyndicated", value: "true"),
            URLQueryItem(name: "q", value: "\(song.title) \(song.artist) official audio"),
            URLQueryItem(name: "key", value: key)
        ]
        guard let url = components.url else { throw YouTubePlaybackError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubePlaybackError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(YouTubeAPIErrorEnvelope.self, from: data))?.error.message
                ?? "HTTP \(http.statusCode)"
            throw YouTubePlaybackError.requestFailed(detail)
        }

        let payload: YouTubeSearchResponse
        do {
            payload = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
        } catch {
            throw YouTubePlaybackError.invalidResponse
        }
        let candidates = payload.items.compactMap { item -> YouTubeSearchCandidate? in
            guard let videoID = item.id.videoID, !videoID.isEmpty else { return nil }
            return YouTubeSearchCandidate(
                videoID: videoID,
                title: item.snippet.title,
                channelTitle: item.snippet.channelTitle
            )
        }
        guard let winner = Self.bestCandidate(in: candidates, for: song) else {
            throw YouTubePlaybackError.noEmbeddableVideo
        }
        return YouTubePlaybackTarget(
            videoID: winner.videoID,
            videoTitle: winner.title,
            channelTitle: winner.channelTitle,
            startOffset: max(0, startOffset)
        )
    }

    static func bestCandidate(
        in candidates: [YouTubeSearchCandidate],
        for song: RecognizedSong
    ) -> YouTubeSearchCandidate? {
        candidates.max { score($0, for: song) < score($1, for: song) }
    }

    private static func score(_ candidate: YouTubeSearchCandidate, for song: RecognizedSong) -> Int {
        let title = normalized(candidate.title)
        let channel = normalized(candidate.channelTitle)
        let songTitle = normalized(song.title)
        let artist = normalized(song.artist)
        var score = 0
        if title.contains(songTitle) { score += 6 }
        if title.contains(artist) { score += 4 }
        if channel.contains(artist) { score += 3 }
        if title.contains("official") || title.contains("audio") || channel.contains("topic") { score += 1 }
        return score
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum YouTubeAPIKeyStore {
    private static let service = "com.example.CoffeeSync.youtube"
    private static let account = "data-api-key"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func save(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

private struct YouTubeSearchResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: Identifier
        let snippet: Snippet
    }

    struct Identifier: Decodable {
        let videoID: String?

        enum CodingKeys: String, CodingKey {
            case videoID = "videoId"
        }
    }

    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
    }
}

private struct YouTubeAPIErrorEnvelope: Decodable {
    let error: Detail

    struct Detail: Decodable {
        let message: String
    }
}
