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
    @Published private(set) var statusDetail = "貼上 AudD token，開始讓 Mac 聽店內音樂。"
    @Published var automaticSwitching = true
    @Published var latencyAdjustment: TimeInterval = 0.70
    @Published var audDToken: String
    @Published var preserveDiagnosticAudio = true
    @Published private(set) var latestDiagnosticLog: URL?

    private let recorder = AudioClipRecorder()
    private let recognizer = AudDRecognitionEngine()
    private let playback = MusicAppPlaybackEngine()
    private let planner = SyncPlanner(startupAllowance: 0.55)
    private var switchGate = TrackSwitchGate(minimumSwitchInterval: 15)
    private var nextCycle: Task<Void, Never>?
    private var sessionIsActive = false

    init() {
        audDToken = AudDTokenStore.load()
        recorder.onClipFinished = { [weak self] url in
            Task { @MainActor in
                await self?.recognize(url)
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

    func toggleSession() {
        sessionIsActive ? stopSession() : startSession()
    }

    func startSession() {
        let token = audDToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            phase = .needsToken
            statusDetail = "先貼上 AudD API token 並儲存，才能辨識環境音。"
            return
        }
        saveToken()
        sessionIsActive = true
        switchGate.reset()
        sessionStartedAt = .now
        requestMicrophoneAndStart()
    }

    func stopSession() {
        sessionIsActive = false
        nextCycle?.cancel()
        nextCycle = nil
        recorder.cancel()
        playback.stop()
        switchGate.reset()
        currentPlan = nil
        sessionStartedAt = nil
        phase = .idle
        statusDetail = "工作階段已結束。"
    }

    private func requestMicrophoneAndStart() {
        Task {
            phase = .requestingMicrophone
            statusDetail = "macOS 會要求允許 CoffeeSync 使用麥克風。"
            let granted = await requestMicrophoneAccess()
            guard granted else {
                sessionIsActive = false
                phase = .unavailable("麥克風權限未允許")
                statusDetail = "CoffeeSync 不會保存錄音；它只會上傳單次 10 秒片段給 AudD 辨識。"
                return
            }
            startRecognitionCycle()
        }
    }

    private func startRecognitionCycle() {
        guard sessionIsActive else { return }
        do {
            phase = .recording
            statusDetail = "正在擷取 10 秒環境音，使用 Mac 內建麥克風效果最佳。"
            try recorder.record(duration: 10)
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
        statusDetail = "正在將短音訊片段送到 AudD 辨識。"

        let attemptID = UUID()
        let preservedAudioURL: URL?
        if preserveDiagnosticAudio {
            do {
                preservedAudioURL = try RecognitionDiagnosticsStore.preserveAudioClip(at: url, attemptID: attemptID)
            } catch {
                preservedAudioURL = nil
                statusDetail = "錄音已送 AudD，但無法保留診斷 WAV：\(error.localizedDescription)"
            }
        } else {
            preservedAudioURL = nil
        }

        let attempt = await recognizer.recognize(fileAt: url, token: audDToken, attemptID: attemptID)
        do {
            latestDiagnosticLog = try RecognitionDiagnosticsStore.writeLog(
                diagnostic: attempt.diagnostic,
                preservedAudioURL: preservedAudioURL,
                song: attempt.song
            )
        } catch {
            latestDiagnosticLog = nil
            statusDetail = "AudD 已回覆，但無法寫入診斷 log：\(error.localizedDescription)"
        }

        if let song = attempt.song {
            await handleRecognition(song)
        } else {
            let reason = attempt.failureDescription ?? "AudD 未提供辨識結果。"
            phase = .unavailable(reason)
            statusDetail = latestDiagnosticLog == nil ? reason : "\(reason) 已儲存診斷 log。"
            scheduleNextRecognition(after: 18)
        }
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
        statusDetail = "Music.app 將從第 \(time(plan.targetOffset)) 接手播放。"

        do {
            try playback.play(song, from: plan.targetOffset)
            switchGate.commitAttempt(for: song)
            phase = .playing(song, plan)
            statusDetail = "已要求 Music.app 同步播放；第一次會請你允許控制 Music。"
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
