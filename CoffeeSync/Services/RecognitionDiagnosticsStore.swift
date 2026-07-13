import Foundation

struct RecognitionDiagnosticLog: Codable {
    let diagnostic: RecognitionDiagnostic
    let preservedAudioFilename: String?
    let recognizedSong: LoggedSong?

    struct LoggedSong: Codable {
        let title: String
        let artist: String
        let matchOffset: TimeInterval
        let appleMusicURL: String?

        init(_ song: RecognizedSong) {
            title = song.title
            artist = song.artist
            matchOffset = song.matchOffset
            appleMusicURL = song.musicURL?.absoluteString
        }
    }
}

enum RecognitionDiagnosticsStore {
    static let maximumRetainedAttempts = 25

    static func diagnosticsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("CoffeeSync", isDirectory: true)
            .appendingPathComponent("Recognition Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func preserveAudioClip(at sourceURL: URL, attemptID: UUID) throws -> URL {
        let destination = try diagnosticsDirectory()
            .appendingPathComponent("\(attemptID.uuidString).wav")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        pruneRetainedAttempts()
        return destination
    }

    @discardableResult
    static func writeLog(
        diagnostic: RecognitionDiagnostic,
        preservedAudioURL: URL?,
        song: RecognizedSong?
    ) throws -> URL {
        let log = RecognitionDiagnosticLog(
            diagnostic: diagnostic,
            preservedAudioFilename: preservedAudioURL?.lastPathComponent,
            recognizedSong: song.map(RecognitionDiagnosticLog.LoggedSong.init)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let destination = try diagnosticsDirectory()
            .appendingPathComponent("\(diagnostic.attemptID.uuidString).json")
        try encoder.encode(log).write(to: destination, options: .atomic)
        pruneRetainedAttempts()
        return destination
    }

    private static func pruneRetainedAttempts() {
        guard let directory = try? diagnosticsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.creationDateKey],
                  options: [.skipsHiddenFiles]
              ) else { return }

        let attemptIDs = Dictionary(grouping: files) { $0.deletingPathExtension().lastPathComponent }
            .sorted { left, right in
                let leftDate = left.value.compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }.max() ?? .distantPast
                let rightDate = right.value.compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }.max() ?? .distantPast
                return leftDate > rightDate
            }

        for attempt in attemptIDs.dropFirst(maximumRetainedAttempts) {
            attempt.value.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
}
