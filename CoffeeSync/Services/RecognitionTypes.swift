import Foundation

struct RecognitionDiagnostic: Codable, Sendable {
    let attemptID: UUID
    let provider: String
    let recordedAt: Date
    let sourceFilename: String
    let audioByteCount: Int?
    let httpStatusCode: Int?
    let serviceStatus: String?
    let errorDescription: String?
    let responseExcerpt: String?
}

struct RecognitionAttempt: Sendable {
    let song: RecognizedSong?
    let diagnostic: RecognitionDiagnostic

    var failureDescription: String? { diagnostic.errorDescription }
}
