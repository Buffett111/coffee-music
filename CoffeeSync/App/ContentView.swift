import SwiftUI

struct ContentView: View {
    @StateObject private var model = CoffeeSessionViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.06, blue: 0.04), Color(red: 0.30, green: 0.17, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    tokenCard
                    sessionButton
                    statusCard
                    playbackCard
                    controlsCard
                    privacyNote
                }
                .frame(maxWidth: 720)
                .padding(28)
            }
        }
        .frame(minWidth: 640, minHeight: 760)
        .tint(.orange)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("CoffeeSync for Mac")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("AudD 辨識店內音樂，讓 Music.app 在耳機裡接手播放。")
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
    }

    private var tokenCard: some View {
        card {
            Label("AudD 連線設定", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                SecureField("貼上 AudD API token", text: $model.audDToken)
                    .textFieldStyle(.roundedBorder)
                Button("儲存至 Keychain", action: model.saveToken)
                    .buttonStyle(.borderedProminent)
            }
            Text("Token 只保存在這台 Mac 的 Keychain，不會寫入專案或 Git。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var sessionButton: some View {
        Button(action: model.toggleSession) {
            Label(model.isActive ? "結束咖啡工作階段" : "開始咖啡工作階段", systemImage: model.isActive ? "stop.fill" : "waveform")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isActive ? .red : .orange)
        .controlSize(.large)
    }

    private var statusCard: some View {
        card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.phase.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(model.statusDetail)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var playbackCard: some View {
        if let song = model.lastRecognition {
            card {
                Label("最近辨識", systemImage: "music.note.list")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(song.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(song.artist)
                    .foregroundStyle(.white.opacity(0.72))
                if let plan = model.currentPlan {
                    Divider().overlay(.white.opacity(0.18)).padding(.vertical, 4)
                    Label("Music.app 從 \(format(plan.targetOffset)) 開始播放", systemImage: "scope")
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
    }

    private var controlsCard: some View {
        card {
            Toggle("辨識後自動控制 Music.app", isOn: $model.automaticSwitching)
                .foregroundStyle(.white)
            Divider().overlay(.white.opacity(0.18)).padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("啟動與耳機延遲微調").foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "+%.2fs", model.latencyAdjustment))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                Slider(value: $model.latencyAdjustment, in: 0...2, step: 0.05)
            }
            Divider().overlay(.white.opacity(0.18)).padding(.vertical, 6)
            Toggle("開發診斷：保留每輪 WAV 與辨識 log", isOn: $model.preserveDiagnosticAudio)
                .foregroundStyle(.white)
            HStack {
                Button("開啟診斷資料夾", action: model.openDiagnosticsFolder)
                    .buttonStyle(.bordered)
                if let log = model.latestDiagnosticLog {
                    Text("最近 log：\(log.lastPathComponent)")
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
    }

    private var privacyNote: some View {
        Label("開發診斷啟用時，每輪 10 秒 WAV 與 AudD 回應摘要會保存在本機；可隨時關閉。請勿分享含有店內談話的錄音。", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.62))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusIcon: String {
        switch model.phase {
        case .idle: "cup.and.saucer"
        case .needsToken: "key.slash"
        case .requestingMicrophone: "lock.shield"
        case .recording: "waveform"
        case .recognizing: "sparkle.magnifyingglass"
        case .listening: "clock.arrow.circlepath"
        case .switching: "arrow.triangle.2.circlepath"
        case .playing: "play.circle.fill"
        case .unavailable: "music.note.slash"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
