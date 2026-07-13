import AVFoundation
import Combine
import Foundation

@MainActor
final class CoffeeSessionViewModel: ObservableObject {
    @Published private(set) var phase: CoffeeSessionPhase = .idle
    @Published private(set) var lastRecognition: RecognizedSong?
    @Published private(set) var currentPlan: PlaybackPlan?
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var statusDetail = "戴上降噪耳機後，開始一段咖啡工作階段。"
    @Published var automaticSwitching = true
    @Published var latencyAdjustment: TimeInterval = 0.20

    private let recognizer = ShazamRecognitionEngine()
    private let playback = AppleMusicPlaybackEngine()
    private let planner = SyncPlanner()
    private var switchGate = TrackSwitchGate()

    init() {
        recognizer.onMatch = { [weak self] song in
            Task { @MainActor in
                await self?.handleRecognition(song)
            }
        }
        recognizer.onError = { [weak self] message in
            Task { @MainActor in
                self?.statusDetail = "辨識服務：\(message)"
            }
        }
    }

    var isActive: Bool {
        switch phase {
        case .listening, .switching, .playing: true
        default: false
        }
    }

    func toggleSession() {
        isActive ? stopSession() : startSession()
    }

    func startSession() {
        Task {
            guard AudioRouteMonitor.hasHeadphones else {
                phase = .needsHeadphones
                statusDetail = "為避免把 Apple Music 播回店內，請先連接有降噪功能的耳機。"
                return
            }

            phase = .requestingPermissions
            statusDetail = "正在要求麥克風與 Apple Music 權限。"

            let microphoneGranted = await AVAudioApplication.requestRecordPermission()
            guard microphoneGranted else {
                phase = .unavailable("麥克風權限未允許")
                statusDetail = "CoffeeSync 不會儲存錄音；它需要麥克風建立音樂指紋。"
                return
            }

            do {
                try await playback.requestAuthorization()
                try recognizer.start()
                switchGate.reset()
                sessionStartedAt = .now
                phase = .listening
                statusDetail = "正在以 Apple 的音樂指紋辨識店內歌曲。"
            } catch {
                phase = .failed(error.localizedDescription)
                statusDetail = error.localizedDescription
            }
        }
    }

    func stopSession() {
        recognizer.stop()
        Task { await playback.stop() }
        switchGate.reset()
        currentPlan = nil
        sessionStartedAt = nil
        phase = .idle
        statusDetail = "工作階段已結束。"
    }

    private func handleRecognition(_ song: RecognizedSong) async {
        lastRecognition = song

        guard automaticSwitching else {
            statusDetail = "已辨識 \(song.displayName)，等待你手動切換。"
            return
        }

        guard switchGate.beginAttempt(for: song) else {
            statusDetail = "持續確認 \(song.title)；維持目前播放。"
            return
        }

        let plan = planner.plan(
            for: song,
            outputLatency: AudioRouteMonitor.estimatedOutputLatency + latencyAdjustment
        )
        currentPlan = plan
        phase = .switching(song)
        statusDetail = "從第 \(time(plan.targetOffset)) 對時接手播放。"

        do {
            try await playback.play(song, from: plan.targetOffset)
            switchGate.commitAttempt(for: song)
            phase = .playing(song, plan)
            statusDetail = "已在耳機中同步播放；店內背景聲會由降噪耳機降低。"
        } catch {
            switchGate.cancelAttempt()
            phase = .unavailable(error.localizedDescription)
            statusDetail = error.localizedDescription
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
