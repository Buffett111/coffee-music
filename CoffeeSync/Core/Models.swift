import Foundation

enum RecognitionProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case audD
    case shazamIO
    case comparison

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .audD: "AudD"
        case .shazamIO: "ShazamIO（開發基線）"
        case .comparison: "雙重比較（同一段 WAV）"
        }
    }

    var recognitionDescription: String {
        switch self {
        case .audD: "AudD 正在辨識"
        case .shazamIO: "ShazamIO 正在辨識"
        case .comparison: "AudD 與 ShazamIO 正在辨識同一段 WAV"
        }
    }

    var requiresAudDToken: Bool { self == .audD || self == .comparison }
    var requiresShazamIO: Bool { self == .shazamIO || self == .comparison }
}

enum CaptureDurationOption: Int, CaseIterable, Identifiable, Sendable {
    case five = 5
    case eight = 8
    case ten = 10

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var displayName: String { "\(rawValue) 秒" }
}

struct RecognitionComparison: Equatable, Sendable {
    struct Result: Equatable, Sendable {
        let provider: RecognitionProvider
        let song: RecognizedSong?
        let failureDescription: String?

        var displayText: String {
            if let song { return song.displayName }
            return failureDescription ?? "未辨識"
        }
    }

    let audD: Result
    let shazamIO: Result
}

struct RecognizedSong: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    /// Optional catalog URL returned by the recognition provider.
    let musicURL: URL?
    /// The point in the catalog recording at which the provider found the match.
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
        case .recognizing: "正在辨識"
        case .listening: "等待下一輪辨識"
        case .switching: "正在對時切換"
        case .playing: "已同步播放"
        case .unavailable: "目前無法播放"
        case .failed: "工作階段已暫停"
        }
    }
}
