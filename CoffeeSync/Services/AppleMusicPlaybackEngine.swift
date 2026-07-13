import Foundation
import MusicKit

enum AppleMusicPlaybackError: LocalizedError {
    case authorizationDenied
    case missingCatalogID
    case catalogItemUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationDenied: "請允許 CoffeeSync 使用 Apple Music，並確認帳號有可播放的訂閱。"
        case .missingCatalogID: "這首現場歌曲沒有可用的 Apple Music 對應版本。"
        case .catalogItemUnavailable: "此 Apple Music 曲目在目前的 Storefront 無法播放。"
        }
    }
}

@MainActor
final class AppleMusicPlaybackEngine {
    private let player = ApplicationMusicPlayer.shared

    func requestAuthorization() async throws {
        guard await MusicAuthorization.request() == .authorized else {
            throw AppleMusicPlaybackError.authorizationDenied
        }
    }

    func play(_ song: RecognizedSong, from offset: TimeInterval) async throws {
        let catalogSong = try await resolveCatalogSong(for: song)

        player.queue = [catalogSong]
        try await player.play()
        player.playbackTime = offset
    }

    func stop() async {
        player.stop()
    }

    private func resolveCatalogSong(for song: RecognizedSong) async throws -> Song {
        if let appleMusicID = song.appleMusicID {
            let itemID = MusicItemID(appleMusicID)
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
            let response = try await request.response()
            if let catalogSong = response.items.first {
                return catalogSong
            }
        }

        // Some Shazam catalog matches do not expose an Apple Music ID.  Falling
        // back to a narrow title-and-artist search keeps the automatic experience
        // intact while still preferring an exact normalized-title match.
        let search = MusicCatalogSearchRequest(
            term: "\(song.title) \(song.artist)",
            types: [Song.self]
        )
        let response = try await search.response()
        let normalizedTitle = song.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let exactTitle = response.songs.first(where: {
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalizedTitle
        }) {
            return exactTitle
        }
        guard let candidate = response.songs.first else {
            throw song.appleMusicID == nil ? AppleMusicPlaybackError.missingCatalogID : AppleMusicPlaybackError.catalogItemUnavailable
        }
        return candidate
    }
}
