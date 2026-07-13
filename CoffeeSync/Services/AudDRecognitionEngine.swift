import Foundation

enum AudDError: LocalizedError {
    case missingToken
    case invalidResponse
    case recognitionFailed(String)
    case noMatch

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "請先在設定貼上 AudD API token。"
        case .invalidResponse:
            "AudD 回傳的資料格式無法辨識。"
        case let .recognitionFailed(message):
            "AudD 辨識失敗：\(message)"
        case .noMatch:
            "這段環境音沒有辨識到歌曲；稍後會再試一次。"
        }
    }
}

struct RecognitionDiagnostic: Codable, Sendable {
    let attemptID: UUID
    let provider: RecognitionProvider
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

/// Recognizes a short microphone recording with AudD's music-recognition API.
final class AudDRecognitionEngine {
    private let endpoint = URL(string: "https://api.audd.io/")!

    func recognize(
        fileAt fileURL: URL,
        token: String,
        attemptID: UUID = UUID()
    ) async -> RecognitionAttempt {
        let recordedAt = Date()
        let filename = fileURL.lastPathComponent
        let byteCount = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return failedAttempt(
                attemptID: attemptID,
                recordedAt: recordedAt,
                filename: filename,
                byteCount: byteCount,
                error: AudDError.missingToken
            )
        }

        let audio: Data
        do {
            audio = try Data(contentsOf: fileURL)
        } catch {
            return failedAttempt(
                attemptID: attemptID,
                recordedAt: recordedAt,
                filename: filename,
                byteCount: byteCount,
                error: error
            )
        }
        let boundary = "CoffeeSync-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body = Data()
        body.appendFormField(name: "api_token", value: token, boundary: boundary)
        body.appendFormField(name: "return", value: "apple_music,spotify", boundary: boundary)
        body.appendFile(
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/wav",
            data: audio,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            let httpStatusCode = (response as? HTTPURLResponse)?.statusCode
            let responseDetails = responseDetails(from: data)

            guard let httpStatusCode, 200 ..< 300 ~= httpStatusCode else {
                return failedAttempt(
                    attemptID: attemptID,
                    recordedAt: recordedAt,
                    filename: filename,
                    byteCount: byteCount,
                    httpStatusCode: httpStatusCode,
                    serviceStatus: responseDetails.status,
                    responseExcerpt: responseExcerpt(from: data),
                    error: AudDError.recognitionFailed("AudD HTTP \(httpStatusCode.map(String.init) ?? "未知")")
                )
            }

            do {
                let song = try decodeRecognition(data)
                return RecognitionAttempt(
                    song: song,
                    diagnostic: RecognitionDiagnostic(
                        attemptID: attemptID,
                        provider: .audD,
                        recordedAt: recordedAt,
                        sourceFilename: filename,
                        audioByteCount: byteCount,
                        httpStatusCode: httpStatusCode,
                        serviceStatus: responseDetails.status,
                        errorDescription: nil,
                        responseExcerpt: responseExcerpt(from: data)
                    )
                )
            } catch {
                return failedAttempt(
                    attemptID: attemptID,
                    recordedAt: recordedAt,
                    filename: filename,
                    byteCount: byteCount,
                    httpStatusCode: httpStatusCode,
                    serviceStatus: responseDetails.status,
                    responseExcerpt: responseExcerpt(from: data),
                    error: error
                )
            }
        } catch {
            return failedAttempt(
                attemptID: attemptID,
                recordedAt: recordedAt,
                filename: filename,
                byteCount: byteCount,
                error: error
            )
        }
    }

    func decodeRecognition(_ data: Data) throws -> RecognizedSong {
        let decoded: AudDResponse
        do {
            decoded = try JSONDecoder().decode(AudDResponse.self, from: data)
        } catch {
            throw AudDError.invalidResponse
        }

        guard decoded.status == "success" else {
            throw AudDError.recognitionFailed(decoded.error?.errorMessage ?? decoded.status)
        }
        guard let result = decoded.result else { throw AudDError.noMatch }

        let musicURL = result.appleMusic?.url.flatMap(URL.init(string:))
        return RecognizedSong(
            title: result.title,
            artist: result.artist,
            musicURL: musicURL,
            matchOffset: AudDTimecode.seconds(from: result.timecode),
            receivedAt: .now
        )
    }

    private func failedAttempt(
        attemptID: UUID,
        recordedAt: Date,
        filename: String,
        byteCount: Int?,
        httpStatusCode: Int? = nil,
        serviceStatus: String? = nil,
        responseExcerpt: String? = nil,
        error: Error
    ) -> RecognitionAttempt {
        RecognitionAttempt(
            song: nil,
            diagnostic: RecognitionDiagnostic(
                attemptID: attemptID,
                provider: .audD,
                recordedAt: recordedAt,
                sourceFilename: filename,
                audioByteCount: byteCount,
                httpStatusCode: httpStatusCode,
                serviceStatus: serviceStatus,
                errorDescription: error.localizedDescription,
                responseExcerpt: responseExcerpt
            )
        )
    }

    private func responseDetails(from data: Data) -> (status: String?, error: String?) {
        guard let response = try? JSONDecoder().decode(AudDResponse.self, from: data) else {
            return (nil, nil)
        }
        return (response.status, response.error?.errorMessage)
    }

    private func responseExcerpt(from data: Data, limit: Int = 16_384) -> String? {
        let prefix = data.prefix(limit)
        guard var text = String(data: prefix, encoding: .utf8) else { return nil }
        if data.count > limit { text += "\n[response truncated at \(limit) bytes]" }
        return text
    }
}

enum AudDTimecode {
    static func seconds(from timecode: String?) -> TimeInterval {
        guard let timecode else { return 0 }
        let values = timecode.split(separator: ":").compactMap { Double($0) }
        guard !values.isEmpty else { return 0 }
        return values.reversed().enumerated().reduce(0) { partial, component in
            partial + component.element * pow(60, Double(component.offset))
        }
    }
}

private struct AudDResponse: Decodable {
    let status: String
    let result: AudDResult?
    let error: AudDAPIError?
}

private struct AudDAPIError: Decodable {
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case errorMessage = "error_message"
    }
}

private struct AudDResult: Decodable {
    let title: String
    let artist: String
    let timecode: String?
    let appleMusic: AudDAppleMusic?

    enum CodingKeys: String, CodingKey {
        case title, artist, timecode
        case appleMusic = "apple_music"
    }
}

private struct AudDAppleMusic: Decodable {
    let url: String?
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append(value.data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
