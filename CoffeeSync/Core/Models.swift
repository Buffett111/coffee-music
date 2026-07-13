import Foundation

struct RecognizedSong: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    /// AudD's Apple Music link, used only as a fallback if the song is absent
    /// from the user's synced Music library.
    let musicURL: URL?
    /// The point in the catalog recording at which AudD found the match.
    let matchOffset: TimeInterval
    /// When the framework delivered this result to the app.
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        musicURL: URL?,
        matchOffset: TimeInterval,
        receivedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.musicURL = musicURL
        self.matchOffset = matchOffset
        self.receivedAt = receivedAt
    }

    var displayName: String { "\(title) — \(artist)" }

    var stableIdentity: String {
        musicURL?.absoluteString ?? "\(title.lowercased())|\(artist.lowercased())"
    }
}

struct PlaybackPlan: Equatable, Sendable {
    let targetOffset: TimeInterval
    let estimatedDrift: TimeInterval
    let explanation: String
}

enum CoffeeSessionPhase: Equatable {
    case idle
    case needsToken
    case requestingMicrophone
    case recording
    case recognizing
    case listening
    case switching(RecognizedSong)
    case playing(RecognizedSong, PlaybackPlan)
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle: "準備開始"
        case .needsToken: "需要 AudD token"
        case .requestingMicrophone: "正在取得麥克風權限"
        case .recording: "正在擷取環境音"
        case .recognizing: "AudD 正在辨識"
        case .listening: "等待下一輪辨識"
        case .switching: "正在對時切換"
        case .playing: "已同步播放"
        case .unavailable: "目前無法播放"
        case .failed: "工作階段已暫停"
        }
    }
}
