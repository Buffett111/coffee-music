import Foundation

struct RecognizedSong: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let appleMusicID: String?
    /// The point in the catalog recording at which ShazamKit found the match.
    let matchOffset: TimeInterval
    /// When the framework delivered this result to the app.
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        appleMusicID: String?,
        matchOffset: TimeInterval,
        receivedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.appleMusicID = appleMusicID
        self.matchOffset = matchOffset
        self.receivedAt = receivedAt
    }

    var displayName: String { "\(title) — \(artist)" }

    var stableIdentity: String {
        appleMusicID ?? "\(title.lowercased())|\(artist.lowercased())"
    }
}

struct PlaybackPlan: Equatable, Sendable {
    let targetOffset: TimeInterval
    let estimatedDrift: TimeInterval
    let explanation: String
}

enum CoffeeSessionPhase: Equatable {
    case idle
    case needsHeadphones
    case requestingPermissions
    case listening
    case switching(RecognizedSong)
    case playing(RecognizedSong, PlaybackPlan)
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle: "準備開始"
        case .needsHeadphones: "請先連接耳機"
        case .requestingPermissions: "正在取得權限"
        case .listening: "正在聽店內音樂"
        case .switching: "正在對時切換"
        case .playing: "已同步播放"
        case .unavailable: "目前無法播放"
        case .failed: "工作階段已暫停"
        }
    }
}
