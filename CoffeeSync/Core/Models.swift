import Foundation

enum CaptureDurationOption: Int, CaseIterable, Identifiable, Sendable {
    case five = 5
    case eight = 8
    case ten = 10

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var displayName: String { "\(rawValue) 秒" }
}

struct RecognizedSong: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    /// The point in the recording at which ShazamIO found the match.
    let matchOffset: TimeInterval
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        matchOffset: TimeInterval,
        receivedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.matchOffset = matchOffset
        self.receivedAt = receivedAt
    }

    var displayName: String { "\(title) — \(artist)" }
    var stableIdentity: String { "\(title.lowercased())|\(artist.lowercased())" }
}

struct PlaybackPlan: Equatable, Sendable {
    let targetOffset: TimeInterval
    let estimatedDrift: TimeInterval
    let explanation: String
}

/// A one-shot relative seek that keeps the currently playing YouTube video in
/// sync when the user changes the extra delay slider.
struct YouTubeSeekCommand: Equatable, Identifiable, Sendable {
    let id = UUID()
    let delta: TimeInterval
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
        case .needsToken: "需要 YouTube API key"
        case .requestingMicrophone: "正在取得麥克風權限"
        case .recording: "正在擷取環境音"
        case .recognizing: "正在辨識"
        case .listening: "等待下一輪辨識"
        case .switching: "正在對時切換"
        case .playing: "已同步播放"
        case .unavailable: "目前無法播放"
        case .failed: "同步已暫停"
        }
    }
}
