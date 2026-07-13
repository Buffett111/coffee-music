import AVFoundation
import Foundation

enum AudioClipRecorderError: LocalizedError {
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .inputUnavailable: "找不到可用的麥克風輸入。"
        }
    }
}

/// Records one short WAV clip. CoffeeSessionViewModel deletes it after AudD
/// processes it, or copies it to the local diagnostics folder when enabled.
final class AudioClipRecorder {
    var onClipFinished: ((URL) -> Void)?
    var onRecordingError: ((Error) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var pendingFinish: DispatchWorkItem?
    private var recordingURL: URL?
    private var recordingDuration: TimeInterval = 5
    private var routeRestartIsPending = false
    private var configurationObserver: NSObjectProtocol?
    private(set) var isRecording = false

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    func record(duration: TimeInterval = 5) throws {
        guard !isRecording else { return }
        let input = audioEngine.inputNode
        audioEngine.reset()
        // `outputFormat` can retain a client format from the previous audio route
        // (for example 48 kHz before AirPods switch the input to 24 kHz). The input
        // format is the current hardware format and is safe for the WAV file.
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioClipRecorderError.inputUnavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoffeeSync-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url
        // Passing nil makes AVAudioEngine use its current node format instead of
        // applying a stale client format during a route/configuration transition.
        input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            recordingURL = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        isRecording = true
        recordingDuration = duration

        let work = DispatchWorkItem { [weak self] in self?.finishRecording() }
        pendingFinish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func cancel() {
        pendingFinish?.cancel()
        pendingFinish = nil
        finishRecording(deliver: false)
    }

    private func finishRecording(deliver: Bool = true) {
        guard isRecording else { return }
        pendingFinish = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil
        isRecording = false

        let finishedURL = recordingURL
        self.recordingURL = nil
        guard deliver, let finishedURL else {
            if let finishedURL { try? FileManager.default.removeItem(at: finishedURL) }
            return
        }
        onClipFinished?(finishedURL)
    }

    private func restartAfterConfigurationChange() {
        guard isRecording, !routeRestartIsPending else { return }
        routeRestartIsPending = true
        let duration = recordingDuration
        finishRecording(deliver: false)

        // AVAudioEngine may report the change while Core Audio is still rebuilding
        // the device graph. Restarting on the next main-loop turn gives it a stable
        // current input format instead of reusing the departed device's format.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.routeRestartIsPending = false
            do {
                try self.record(duration: duration)
            } catch {
                self.onRecordingError?(error)
            }
        }
    }
}
