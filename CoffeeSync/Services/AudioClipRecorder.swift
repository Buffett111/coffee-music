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

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var pendingFinish: DispatchWorkItem?
    private var recordingURL: URL?
    private(set) var isRecording = false

    func record(duration: TimeInterval = 10) throws {
        guard !isRecording else { return }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioClipRecorderError.inputUnavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoffeeSync-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

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

        guard deliver, let recordingURL else { return }
        self.recordingURL = nil
        onClipFinished?(recordingURL)
    }
}
