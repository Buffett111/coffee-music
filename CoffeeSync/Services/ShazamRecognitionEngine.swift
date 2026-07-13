import AVFoundation
import ShazamKit

/// Owns the microphone tap and provides live ShazamKit catalog matches.
final class ShazamRecognitionEngine: NSObject {
    var onMatch: ((RecognizedSong) -> Void)?
    var onError: ((String) -> Void)?

    private let session = SHSession()
    private let audioEngine = AVAudioEngine()
    private var isRunning = false

    override init() {
        super.init()
        session.delegate = self
    }

    func start() throws {
        guard !isRunning else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetoothA2DP, .allowBluetoothHFP]
        )
        try audioSession.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        let matchingSession: SHSession = session
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { buffer, timestamp in
            matchingSession.matchStreamingBuffer(buffer, at: timestamp)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
    }
}

extension ShazamRecognitionEngine: SHSessionDelegate {
    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        onMatch?(
            RecognizedSong(
                title: item.title ?? "Unknown track",
                artist: item.artist ?? "Unknown artist",
                appleMusicID: item.appleMusicID,
                matchOffset: item.matchOffset,
                receivedAt: .now
            )
        )
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        if let error {
            onError?(error.localizedDescription)
        }
    }
}
