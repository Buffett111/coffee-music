import Foundation

enum ShazamIORecognitionError: LocalizedError {
    case benchmarkUnavailable(String)
    case invalidRunnerResponse
    case runnerFailed(String)
    case noMatch

    var errorDescription: String? {
        switch self {
        case let .benchmarkUnavailable(detail):
            "ShazamIO 開發基線不可用：\(detail)"
        case .invalidRunnerResponse:
            "ShazamIO runner 回傳的資料格式無法辨識。"
        case let .runnerFailed(detail):
            "ShazamIO runner 失敗：\(detail)"
        case .noMatch:
            "ShazamIO 沒有辨識到這段歌曲；稍後會再試一次。"
        }
    }
}

/// Bridge to the ShazamIO runtime bundled as an app resource.
final class ShazamIORecognitionEngine {
    struct Environment: Sendable {
        let root: URL
        let python: URL
        let recognizeScript: URL
        let selfCheckScript: URL

        static func bundledRuntime() -> Environment {
            let root = Bundle(for: ShazamIORecognitionEngine.self).resourceURL?
                .appendingPathComponent("ShazamIO", isDirectory: true)
                ?? URL(fileURLWithPath: "/ShazamIO-runtime-missing", isDirectory: true)
            return Environment(
                root: root,
                python: root.appendingPathComponent("python/bin/python3.10", isDirectory: false),
                recognizeScript: root.appendingPathComponent("recognize.py", isDirectory: false),
                selfCheckScript: root.appendingPathComponent("self_check.py", isDirectory: false)
            )
        }
    }

    struct SelfCheck: Decodable, Sendable {
        let status: String
        let shazamio: String
        let shazamioCore: String
        let networkRequestMade: Bool
    }

    private let environment: Environment

    init(environment: Environment = .bundledRuntime()) {
        self.environment = environment
    }

    var setupDescription: String {
        "已內嵌 ShazamIO runtime：\(environment.root.path)"
    }

    func isAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: environment.python.path)
            && FileManager.default.fileExists(atPath: environment.recognizeScript.path)
            && FileManager.default.fileExists(atPath: environment.selfCheckScript.path)
    }

    func selfCheck() async -> Result<SelfCheck, Error> {
        do {
            try requireEnvironment()
            let output = try await run(arguments: [environment.selfCheckScript.path])
            guard output.exitCode == 0 else {
                throw ShazamIORecognitionError.runnerFailed(output.combinedText)
            }
            return .success(try JSONDecoder().decode(SelfCheck.self, from: output.standardOutput))
        } catch {
            return .failure(error)
        }
    }

    func recognize(fileAt fileURL: URL, attemptID: UUID = UUID()) async -> RecognitionAttempt {
        let recordedAt = Date()
        let filename = fileURL.lastPathComponent
        let byteCount = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil

        do {
            try requireEnvironment()
            let output = try await run(arguments: [environment.recognizeScript.path, fileURL.path])
            return try decodeRecognition(
                output.standardOutput,
                attemptID: attemptID,
                recordedAt: recordedAt,
                filename: filename,
                byteCount: byteCount,
                processExitCode: output.exitCode,
                standardError: output.standardError
            )
        } catch {
            return failedAttempt(
                attemptID: attemptID,
                recordedAt: recordedAt,
                filename: filename,
                byteCount: byteCount,
                responseExcerpt: nil,
                error: error
            )
        }
    }

    func decodeRecognition(
        _ data: Data,
        attemptID: UUID,
        recordedAt: Date,
        filename: String,
        byteCount: Int?,
        processExitCode: Int32 = 0,
        standardError: Data = Data()
    ) throws -> RecognitionAttempt {
        let response: RunnerResponse
        do {
            response = try JSONDecoder().decode(RunnerResponse.self, from: data)
        } catch {
            throw ShazamIORecognitionError.invalidRunnerResponse
        }

        let excerpt = responseExcerpt(stdout: data, standardError: standardError, exitCode: processExitCode)
        guard response.recognized,
              let track = response.track,
              !track.title.isEmpty,
              !track.subtitle.isEmpty else {
            let error: Error
            if let message = response.error, !message.isEmpty {
                error = ShazamIORecognitionError.runnerFailed(message)
            } else {
                error = ShazamIORecognitionError.noMatch
            }
            return failedAttempt(
                attemptID: attemptID,
                recordedAt: recordedAt,
                filename: filename,
                byteCount: byteCount,
                responseExcerpt: excerpt,
                error: error
            )
        }

        let song = RecognizedSong(
            title: track.title,
            artist: track.subtitle,
            matchOffset: max(0, response.firstMatch?.offset ?? 0),
            receivedAt: .now
        )
        return RecognitionAttempt(
            song: song,
            diagnostic: RecognitionDiagnostic(
                attemptID: attemptID,
                provider: "ShazamIO",
                recordedAt: recordedAt,
                sourceFilename: filename,
                audioByteCount: byteCount,
                httpStatusCode: nil,
                serviceStatus: "match",
                errorDescription: nil,
                responseExcerpt: excerpt
            )
        )
    }

    private func requireEnvironment() throws {
        guard FileManager.default.isExecutableFile(atPath: environment.python.path) else {
            throw ShazamIORecognitionError.benchmarkUnavailable("找不到 Python：\(environment.python.path)")
        }
        guard FileManager.default.fileExists(atPath: environment.recognizeScript.path),
              FileManager.default.fileExists(atPath: environment.selfCheckScript.path) else {
            throw ShazamIORecognitionError.benchmarkUnavailable("找不到 scripts/recognize.py 或 scripts/self_check.py")
        }
    }

    private func failedAttempt(
        attemptID: UUID,
        recordedAt: Date,
        filename: String,
        byteCount: Int?,
        responseExcerpt: String?,
        error: Error
    ) -> RecognitionAttempt {
        RecognitionAttempt(
            song: nil,
            diagnostic: RecognitionDiagnostic(
                attemptID: attemptID,
                provider: "ShazamIO",
                recordedAt: recordedAt,
                sourceFilename: filename,
                audioByteCount: byteCount,
                httpStatusCode: nil,
                serviceStatus: "no-match",
                errorDescription: error.localizedDescription,
                responseExcerpt: responseExcerpt
            )
        )
    }

    private func run(arguments: [String]) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) { [environment] in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = environment.python
            // The runtime lives inside the signed app bundle. Prevent Python
            // from writing __pycache__ files there during recognition.
            process.arguments = ["-B"] + arguments
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            return ProcessOutput(
                exitCode: process.terminationStatus,
                standardOutput: stdout.fileHandleForReading.readDataToEndOfFile(),
                standardError: stderr.fileHandleForReading.readDataToEndOfFile()
            )
        }.value
    }

    private func responseExcerpt(stdout: Data, standardError: Data, exitCode: Int32) -> String? {
        var parts: [String] = []
        if let text = String(data: stdout.prefix(16_384), encoding: .utf8), !text.isEmpty {
            parts.append("stdout:\n\(text)")
        }
        if let text = String(data: standardError.prefix(4_096), encoding: .utf8), !text.isEmpty {
            parts.append("stderr:\n\(text)")
        }
        if exitCode != 0 { parts.append("runner exit code: \(exitCode)") }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

private struct ProcessOutput: Sendable {
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

private struct RunnerResponse: Decodable {
    let recognized: Bool
    let track: Track?
    let firstMatch: FirstMatch?
    let error: String?

    struct Track: Decodable {
        let title: String
        let subtitle: String
    }

    struct FirstMatch: Decodable {
        let offset: TimeInterval?
    }

    enum CodingKeys: String, CodingKey {
        case recognized, track, error
        case firstMatch = "firstMatch"
    }
}
