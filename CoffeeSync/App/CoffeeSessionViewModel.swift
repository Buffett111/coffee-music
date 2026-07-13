import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class CoffeeSessionViewModel: ObservableObject {
    @Published private(set) var phase: CoffeeSessionPhase = .idle
    @Published private(set) var lastRecognition: RecognizedSong?
    @Published private(set) var currentPlan: PlaybackPlan?
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var statusDetail = "選擇辨識後端，開始讓 Mac 聽店內音樂。"
    @Published var automaticSwitching = true
    /// Extra delay after the fixed five-second capture baseline.
    @Published var latencyAdjustment: TimeInterval = 0
    @Published var recognitionProvider: RecognitionProvider = .audD
    @Published var audDToken: String
    @Published var youTubeAPIKey: String
    @Published var preserveDiagnosticAudio = true
    @Published private(set) var latestDiagnosticLog: URL?
    @Published private(set) var youTubeTarget: YouTubePlaybackTarget?
    @Published private(set) var shazamIOSetupDescription: String
    @Published private(set) var latestComparison: RecognitionComparison?

    private let recorder = AudioClipRecorder()
    private let audDRecognizer = AudDRecognitionEngine()
    private let shazamIORecognizer = ShazamIORecognitionEngine()
    private let playback = YouTubePlaybackEngine()
    private let planner = SyncPlanner(startupAllowance: 0.55, captureDuration: 5)
    private var switchGate = TrackSwitchGate(minimumSwitchInterval: 15)
    private var nextCycle: Task<Void, Never>?
    private var sessionIsActive = false

    init() {
        audDToken = AudDTokenStore.load()
        youTubeAPIKey = YouTubeAPIKeyStore.load()
        shazamIOSetupDescription = shazamIORecognizer.setupDescription
        recorder.onClipFinished = { [weak self] url in
            Task { @MainActor in
                await self?.recognize(url)
            }
        }
        recorder.onRecordingError = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.sessionIsActive = false
                self.phase = .failed(error.localizedDescription)
                self.statusDetail = "耳機或音訊裝置切換後無法重新啟動錄音：\(error.localizedDescription)"
            }
        }
    }

    var isActive: Bool { sessionIsActive }

    func saveToken() {
        do {
            try AudDTokenStore.save(audDToken.trimmingCharacters(in: .whitespacesAndNewlines))
            statusDetail = audDToken.isEmpty ? "AudD token 已從 Keychain 移除。" : "AudD token 已儲存在這台 Mac 的 Keychain。"
        } catch {
            phase = .failed(error.localizedDescription)
            statusDetail = "無法寫入 Keychain：\(error.localizedDescription)"
        }
    }

    func saveYouTubeAPIKey() {
        do {
            try YouTubeAPIKeyStore.save(youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines))
            statusDetail = youTubeAPIKey.isEmpty
                ? "YouTube API key 已從 Keychain 移除。"
                : "YouTube Data API key 已儲存在這台 Mac 的 Keychain。"
        } catch {
            phase = .failed(error.localizedDescription)
            statusDetail = "無法寫入 Keychain：\(error.localizedDescription)"
        }
    }

    func toggleSession() {
        sessionIsActive ? stopSession() : startSession()
    }

    func startSession() {
        let token = audDToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recognitionProvider.requiresAudDToken || !token.isEmpty else {
            phase = .needsToken
            statusDetail = "先貼上 AudD API token 並儲存，才能辨識環境音。"
            return
        }
        guard !recognitionProvider.requiresShazamIO || shazamIORecognizer.isAvailable() else {
            phase = .unavailable("ShazamIO 開發基線不可用")
            statusDetail = "找不到獨立 benchmark runner。\(shazamIOSetupDescription)"
            return
        }
        guard recognitionProvider == .comparison || !youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .needsToken
            statusDetail = "先貼上並儲存 YouTube Data API key，才能在 YouTube 找到對應曲目。"
            return
        }
        if recognitionProvider == .audD { saveToken() }
        if recognitionProvider != .comparison { saveYouTubeAPIKey() }
        sessionIsActive = true
        switchGate.reset()
        latestComparison = nil
        sessionStartedAt = .now
        requestMicrophoneAndStart()
    }

    func stopSession() {
        sessionIsActive = false
        nextCycle?.cancel()
        nextCycle = nil
        recorder.cancel()
        youTubeTarget = nil
        latestComparison = nil
        switchGate.reset()
        currentPlan = nil
        sessionStartedAt = nil
        phase = .idle
        statusDetail = "工作階段已結束。"
    }

    /// Exercises only the YouTube search and embedded-player path. It deliberately
    /// does not request microphone access or upload any audio to AudD.
    func testYouTubePlayback() {
        guard !sessionIsActive else {
            statusDetail = "請先結束咖啡工作階段，再執行獨立 YouTube 播放測試。"
            return
        }
        guard !youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .needsToken
            statusDetail = "請先貼上並儲存 YouTube Data API key。"
            return
        }

        let song = RecognizedSong(
            title: "Wish You The Best",
            artist: "Lewis Capaldi",
            musicURL: nil,
            matchOffset: 0
        )
        let plan = PlaybackPlan(
            targetOffset: 0,
            estimatedDrift: 0,
            explanation: "獨立 YouTube 播放測試"
        )
        lastRecognition = song
        currentPlan = plan
        youTubeTarget = nil
        phase = .switching(song)
        statusDetail = "正在測試 YouTube 搜尋與可見播放器（不會使用麥克風或 AudD）。"

        Task {
            do {
                let target = try await playback.resolve(
                    song: song,
                    apiKey: youTubeAPIKey,
                    startOffset: plan.targetOffset
                )
                youTubeTarget = target
                phase = .playing(song, plan)
                statusDetail = "YouTube 測試已載入「\(target.videoTitle)」，應從開頭播放。"
            } catch {
                phase = .unavailable(error.localizedDescription)
                statusDetail = error.localizedDescription
            }
        }
    }

    /// Runs the bundled runtime's import-only check. It does not ask for the
    /// microphone and does not send any audio or recognition request.
    func testShazamIOEnvironment() {
        guard !sessionIsActive else {
            statusDetail = "請先結束咖啡工作階段，再驗證 ShazamIO 開發基線。"
            return
        }
        phase = .recognizing
        statusDetail = "正在驗證內嵌 ShazamIO 開發基線（不會送出音檔）。"
        Task {
            switch await shazamIORecognizer.selfCheck() {
            case let .success(check):
                phase = .idle
                statusDetail = "ShazamIO \(check.shazamio) / core \(check.shazamioCore) 已就緒；自檢未送出網路請求。"
            case let .failure(error):
                phase = .unavailable(error.localizedDescription)
                statusDetail = error.localizedDescription
            }
        }
    }

    private func requestMicrophoneAndStart() {
        Task {
            phase = .requestingMicrophone
            statusDetail = "macOS 會要求允許 CoffeeSync 使用麥克風。"
            let granted = await requestMicrophoneAccess()
            guard granted else {
                sessionIsActive = false
                phase = .unavailable("麥克風權限未允許")
                statusDetail = "CoffeeSync 不會保存錄音；它只會處理單次 5 秒片段。"
                return
            }
            startRecognitionCycle()
        }
    }

    private func startRecognitionCycle() {
        guard sessionIsActive else { return }
        do {
            phase = .recording
            statusDetail = "正在擷取 5 秒環境音，使用 Mac 內建麥克風效果最佳。"
            try recorder.record(duration: 5)
        } catch {
            sessionIsActive = false
            phase = .failed(error.localizedDescription)
            statusDetail = error.localizedDescription
        }
    }

    private func recognize(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard sessionIsActive else { return }
        phase = .recognizing
        statusDetail = "正在使用 \(recognitionProvider.recognitionDescription)。"

        let attemptID = UUID()
        let preservedAudioURL: URL?
        if preserveDiagnosticAudio {
            do {
                preservedAudioURL = try RecognitionDiagnosticsStore.preserveAudioClip(at: url, attemptID: attemptID)
            } catch {
                preservedAudioURL = nil
                statusDetail = "錄音已送辨識後端，但無法保留診斷 WAV：\(error.localizedDescription)"
            }
        } else {
            preservedAudioURL = nil
        }

        if recognitionProvider == .comparison {
            await compareRecognition(
                fileAt: url,
                preservedAudioURL: preservedAudioURL
            )
            return
        }

        let attempt: RecognitionAttempt
        switch recognitionProvider {
        case .audD:
            attempt = await audDRecognizer.recognize(fileAt: url, token: audDToken, attemptID: attemptID)
        case .shazamIO:
            attempt = await shazamIORecognizer.recognize(fileAt: url, attemptID: attemptID)
        case .comparison:
            preconditionFailure("Comparison mode returns before selecting a single recognizer.")
        }
        do {
            latestDiagnosticLog = try RecognitionDiagnosticsStore.writeLog(
                diagnostic: attempt.diagnostic,
                preservedAudioURL: preservedAudioURL,
                song: attempt.song
            )
        } catch {
            latestDiagnosticLog = nil
            statusDetail = "辨識後端已回覆，但無法寫入診斷 log：\(error.localizedDescription)"
        }

        if let song = attempt.song {
            await handleRecognition(song)
        } else {
            let reason = attempt.failureDescription ?? "辨識後端未提供辨識結果。"
            phase = .unavailable(reason)
            statusDetail = latestDiagnosticLog == nil ? reason : "\(reason) 已儲存診斷 log。"
            scheduleNextRecognition(after: 18)
        }
    }

    private func compareRecognition(fileAt url: URL, preservedAudioURL: URL?) async {
        let audDAttemptID = UUID()
        let shazamIOAttemptID = UUID()
        async let audDAttempt = audDRecognizer.recognize(
            fileAt: url,
            token: audDToken,
            attemptID: audDAttemptID
        )
        async let shazamAttempt = shazamIORecognizer.recognize(
            fileAt: url,
            attemptID: shazamIOAttemptID
        )
        let (audD, shazamIO) = await (audDAttempt, shazamAttempt)

        var writtenLogs: [URL] = []
        for attempt in [audD, shazamIO] {
            if let log = try? RecognitionDiagnosticsStore.writeLog(
                diagnostic: attempt.diagnostic,
                preservedAudioURL: preservedAudioURL,
                song: attempt.song
            ) {
                writtenLogs.append(log)
            }
        }
        latestDiagnosticLog = writtenLogs.last
        latestComparison = RecognitionComparison(
            audD: .init(provider: .audD, song: audD.song, failureDescription: audD.failureDescription),
            shazamIO: .init(provider: .shazamIO, song: shazamIO.song, failureDescription: shazamIO.failureDescription)
        )
        phase = .listening
        statusDetail = "同一段 WAV 比較完成：AudD：\(latestComparison?.audD.displayText ?? "未辨識")；ShazamIO：\(latestComparison?.shazamIO.displayText ?? "未辨識")。此模式不會自動播放。"
        scheduleNextRecognition(after: 45)
    }

    func openDiagnosticsFolder() {
        do {
            let directory = try RecognitionDiagnosticsStore.diagnosticsDirectory()
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } catch {
            statusDetail = "無法開啟診斷資料夾：\(error.localizedDescription)"
        }
    }

    private func handleRecognition(_ song: RecognizedSong) async {
        lastRecognition = song
        guard automaticSwitching else {
            phase = .listening
            statusDetail = "已辨識 \(song.displayName)，已關閉自動播放。"
            scheduleNextRecognition(after: 45)
            return
        }
        guard switchGate.beginAttempt(for: song) else {
            phase = .listening
            statusDetail = "持續確認 \(song.title)；維持目前播放。"
            scheduleNextRecognition(after: 45)
            return
        }

        let plan = planner.plan(for: song, outputLatency: latencyAdjustment)
        currentPlan = plan
        phase = .switching(song)
        statusDetail = "正在 YouTube 尋找 \(song.displayName)。"

        do {
            youTubeTarget = try await playback.resolve(
                song: song,
                apiKey: youTubeAPIKey,
                startOffset: plan.targetOffset
            )
            switchGate.commitAttempt(for: song)
            phase = .playing(song, plan)
            statusDetail = "YouTube 已載入「\(youTubeTarget?.videoTitle ?? song.title)」，從第 \(time(plan.targetOffset)) 開始播放。"
            scheduleNextRecognition(after: 45)
        } catch {
            switchGate.cancelAttempt()
            phase = .unavailable(error.localizedDescription)
            statusDetail = error.localizedDescription
            scheduleNextRecognition(after: 18)
        }
    }

    private func scheduleNextRecognition(after seconds: TimeInterval) {
        nextCycle?.cancel()
        nextCycle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.startRecognitionCycle()
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default: false
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
