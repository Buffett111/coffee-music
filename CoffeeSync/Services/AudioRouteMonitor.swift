import AVFoundation

enum AudioRouteMonitor {
    static var hasHeadphones: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                true
            default:
                false
            }
        }
    }

    static var estimatedOutputLatency: TimeInterval {
        let session = AVAudioSession.sharedInstance()
        return max(0, session.outputLatency + session.ioBufferDuration)
    }
}
