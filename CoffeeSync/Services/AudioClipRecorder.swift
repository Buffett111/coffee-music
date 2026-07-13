import AudioToolbox
import AVFoundation
import Foundation

enum AudioClipRecorderError: LocalizedError {
    case inputUnavailable
    case inputSelectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .inputUnavailable: "找不到可用的麥克風輸入。"
        case let .inputSelectionFailed(status): "無法選取 MacBook 內建麥克風（Core Audio \(status)）。"
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
    private(set) var currentInputDescription = "系統預設麥克風"

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

    @discardableResult
    func record(duration: TimeInterval = 5) throws -> String {
        guard !isRecording else { return currentInputDescription }
        let input = audioEngine.inputNode
        audioEngine.reset()
        currentInputDescription = try selectBuiltInMicrophone(for: input)
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
        return currentInputDescription
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

    /// AVAudioEngine otherwise follows the system-default input, which can switch
    /// to an AirPods microphone while the user only intended to change playback.
    /// Prefer the Mac's built-in input for café recognition; desktop Macs without
    /// one retain their current system input as a safe fallback.
    private func selectBuiltInMicrophone(for input: AVAudioInputNode) throws -> String {
        guard let deviceID = builtInInputDeviceID() else {
            return systemInputDeviceName() ?? "系統預設麥克風"
        }
        guard let audioUnit = input.audioUnit else {
            throw AudioClipRecorderError.inputUnavailable
        }

        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioClipRecorderError.inputSelectionFailed(status) }
        return deviceName(for: deviceID) ?? "MacBook 內建麥克風"
    }

    private func builtInInputDeviceID() -> AudioDeviceID? {
        allAudioDevices().first { deviceID in
            hasInputStreams(deviceID) && transportType(for: deviceID) == kAudioDeviceTransportTypeBuiltIn
        }
    }

    private func allAudioDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount
        ) == noErr else { return [] }

        var devices = [AudioDeviceID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &byteCount,
                buffer.baseAddress!
            )
        }
        return status == noErr ? devices : []
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &byteCount) == noErr,
              byteCount >= MemoryLayout<AudioBufferList>.size else { return false }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(byteCount),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, storage) == noErr else {
            return false
        }
        return storage.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers > 0
    }

    private func transportType(for deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, &value) == noErr else {
            return nil
        }
        return value
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, &value) == noErr else {
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }

    private func systemInputDeviceName() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var byteCount = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount,
            &deviceID
        ) == noErr else { return nil }
        return deviceName(for: deviceID)
    }
}
