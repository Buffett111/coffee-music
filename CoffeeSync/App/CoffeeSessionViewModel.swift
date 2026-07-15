import AVFoundation
import Combine
import Foundation

@MainActor
final class CoffeeSessionViewModel: ObservableObject {
    @Published private(set) var phase: CoffeeSessionPhase = .idle
    @Published private(set) var lastRecognition: RecognizedSong?
    @Published private(set) var currentPlan: PlaybackPlan?
    @Published private(set) var statusDetail = "準備好以 ShazamIO 辨識附近音樂。"
    @Published var automaticSwitching = true
    @Published var latencyAdjustment: TimeInterval = 0 {
        didSet { applyLiveLatencyAdjustment(from: oldValue) }
    }
    @Published var captureDuration: CaptureDurationOption = .ten
    @Published var youTubeAPIKey: String
    @Published private(set) var youTubeTarget: YouTubePlaybackTarget?
    @Published private(set) var playbackSeekCommand: YouTubeSeekCommand?
    @Published private(set) var nextRecognitionAt: Date?

    private let recorder = AudioClipRecorder()
    private let recognizer = ShazamIORecognitionEngine()
    private let playback = YouTubePlaybackEngine()
    private let planner = SyncPlanner(startupAllowance: 0.55)
    private var switchGate = TrackSwitchGate(minimumSwitchInterval: 15)
    private var nextCycle: Task<Void, Never>?
    private var sessionIsActive = false
    private var recognitionGeneration = UUID()

    init() {
        youTubeAPIKey = YouTubeAPIKeyStore.load()
        recorder.onClipFinished = { [weak self] url in
            Task { @MainActor in await self?.recognize(url) }
        }
        recorder.onRecordingError = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.sessionIsActive = false
                self.phase = .failed(error.localizedDescription)
                self.statusDetail = "音訊裝置切換後無法重新啟動錄音：\(error.localizedDescription)"
            }
        }
    }

    var isActive: Bool { sessionIsActive }

    func nextRecognitionMessage(at now: Date) -> String {
        guard sessionIsActive else { return "同步已停止；開始同步後會立即偵測。" }
        if let nextRecognitionAt {
            let seconds = max(0, Int(nextRecognitionAt.timeIntervalSince(now).rounded(.up)))
            return "下一輪偵測將於 \(time(TimeInterval(seconds))) 後開始"
        }
        switch phase {
        case .recording: return "目前正在擷取環境音。"
        case .recognizing: return "目前正在辨識音樂。"
        case .switching: return "目前正在尋找並對時 YouTube 影片。"
        case .requestingMicrophone: return "正在等待麥克風權限。"
        default: return "正在準備下一輪偵測。"
        }
    }

    func saveYouTubeAPIKey() {
        do {
            try YouTubeAPIKeyStore.save(youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines))
            statusDetail = youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "YouTube API key 已從 Keychain 移除。"
                : "YouTube Data API key 已儲存在這台 Mac 的 Keychain。"
        } catch {
            phase = .failed(error.localizedDescription)
            statusDetail = "無法寫入 Keychain：\(error.localizedDescription)"
        }
    }

    func toggleSession() { sessionIsActive ? stopSession() : startSession() }

    func startSession() {
        guard recognizer.isAvailable() else {
            phase = .unavailable("ShazamIO 引擎不可用")
            statusDetail = "找不到 app 內嵌的辨識引擎。請重新安裝 CoffeeSync。"
            return
        }
        guard !youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .needsToken
            statusDetail = "請先貼上並儲存自己的 YouTube Data API key。"
            return
        }
        saveYouTubeAPIKey()
        sessionIsActive = true
        recognitionGeneration = UUID()
        switchGate.reset()
        requestMicrophoneAndStart()
    }

    func stopSession() {
        sessionIsActive = false
        nextCycle?.cancel()
        nextCycle = nil
        nextRecognitionAt = nil
        recognitionGeneration = UUID()
        recorder.cancel()
        youTubeTarget = nil
        switchGate.reset()
        currentPlan = nil
        phase = .idle
        statusDetail = "同步已停止。"
    }

    func resyncNow() {
        guard sessionIsActive else {
            statusDetail = "請先開始同步，才能重新偵測。"
            return
        }
        nextCycle?.cancel()
        nextCycle = nil
        nextRecognitionAt = nil
        recognitionGeneration = UUID()
        switchGate.reset()
        recorder.cancel()
        statusDetail = "正在立即重新偵測環境音。"
        startRecognitionCycle()
    }

    func testYouTubePlayback() {
        guard !sessionIsActive else {
            statusDetail = "請先停止同步，再執行獨立 YouTube 播放測試。"
            return
        }
        guard !youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .needsToken
            statusDetail = "請先貼上並儲存自己的 YouTube Data API key。"
            return
        }

        let song = RecognizedSong(title: "Wish You The Best", artist: "Lewis Capaldi", matchOffset: 0)
        let plan = PlaybackPlan(targetOffset: 0, estimatedDrift: 0, explanation: "YouTube 播放測試")
        lastRecognition = song
        currentPlan = plan
        youTubeTarget = nil
        phase = .switching(song)
        statusDetail = "正在測試 YouTube 搜尋與可見播放器；不會使用麥克風。"

        Task {
            do {
                let target = try await playback.resolve(song: song, apiKey: youTubeAPIKey, startOffset: 0)
                youTubeTarget = target
                phase = .playing(song, plan)
                statusDetail = "YouTube 測試已載入「\(target.videoTitle)」。"
            } catch {
                phase = .unavailable(error.localizedDescription)
                statusDetail = error.localizedDescription
            }
        }
    }

    private func requestMicrophoneAndStart() {
        Task {
            phase = .requestingMicrophone
            statusDetail = "macOS 會要求允許 CoffeeSync 使用麥克風。"
            guard await requestMicrophoneAccess() else {
                sessionIsActive = false
                phase = .unavailable("麥克風權限未允許")
                statusDetail = "CoffeeSync 只會在同步時處理 \(captureDuration.rawValue) 秒錄音片段。"
                return
            }
            startRecognitionCycle()
        }
    }

    private func startRecognitionCycle() {
        guard sessionIsActive else { return }
        nextRecognitionAt = nil
        do {
            phase = .recording
            let input = try recorder.record(duration: captureDuration.seconds)
            statusDetail = "正在用 \(input) 擷取 \(captureDuration.rawValue) 秒環境音。"
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
        statusDetail = "ShazamIO 正在辨識。"

        let attemptID = UUID()
        let generation = recognitionGeneration
        let attempt = await recognizer.recognize(fileAt: url, attemptID: attemptID)
        guard sessionIsActive, generation == recognitionGeneration else { return }
        if let song = attempt.song {
            await handleRecognition(song, generation: generation)
        } else {
            let reason = attempt.failureDescription ?? "ShazamIO 未提供辨識結果。"
            phase = .unavailable(reason)
            statusDetail = reason
            scheduleNextRecognition(after: 18)
        }
    }

    private func handleRecognition(_ song: RecognizedSong, generation: UUID) async {
        lastRecognition = song
        guard automaticSwitching else {
            phase = .listening
            statusDetail = "已辨識 \(song.displayName)，自動播放已關閉。"
            scheduleNextRecognition(after: 60)
            return
        }
        guard switchGate.beginAttempt(for: song) else {
            phase = .listening
            statusDetail = "持續確認 \(song.title)；維持目前 YouTube 播放。"
            scheduleNextRecognition(after: 60)
            return
        }

        let plan = SyncPlanner(
            startupAllowance: planner.startupAllowance,
            captureDuration: captureDuration.seconds
        ).plan(for: song, outputLatency: latencyAdjustment)
        currentPlan = plan
        phase = .switching(song)
        statusDetail = "正在 YouTube 尋找 \(song.displayName)。"

        do {
            youTubeTarget = try await playback.resolve(song: song, apiKey: youTubeAPIKey, startOffset: plan.targetOffset)
            guard sessionIsActive, generation == recognitionGeneration else { return }
            switchGate.commitAttempt(for: song)
            phase = .playing(song, plan)
            statusDetail = "YouTube 已載入「\(youTubeTarget?.videoTitle ?? song.title)」，從 \(time(plan.targetOffset)) 開始播放。"
            scheduleNextRecognition(after: 60)
        } catch {
            switchGate.cancelAttempt()
            phase = .unavailable(error.localizedDescription)
            statusDetail = error.localizedDescription
            scheduleNextRecognition(after: 18)
        }
    }

    private func scheduleNextRecognition(after seconds: TimeInterval) {
        nextCycle?.cancel()
        nextRecognitionAt = Date().addingTimeInterval(seconds)
        nextCycle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.nextRecognitionAt = nil
            self?.startRecognitionCycle()
        }
    }

    private func applyLiveLatencyAdjustment(from previousValue: TimeInterval) {
        let delta = latencyAdjustment - previousValue
        guard abs(delta) >= 0.001, youTubeTarget != nil else { return }
        if let plan = currentPlan {
            currentPlan = PlaybackPlan(
                targetOffset: max(0, plan.targetOffset + delta),
                estimatedDrift: plan.estimatedDrift + delta,
                explanation: plan.explanation
            )
        }
        playbackSeekCommand = YouTubeSeekCommand(delta: delta)
        statusDetail = "已將目前 YouTube 播放位置調整 \(String(format: "%+.2f", delta)) 秒。"
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
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
