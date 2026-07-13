import SwiftUI
import WebKit

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
                    comparisonCard
                    youTubePlayerCard
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
                Text("可切換 AudD 與 ShazamIO 開發基線，讓 YouTube 在耳機裡接手播放。")
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
    }

    private var tokenCard: some View {
        card {
            Label("辨識後端", systemImage: "waveform.badge.magnifyingglass")
                .font(.headline)
                .foregroundStyle(.white)
            Picker("辨識後端", selection: $model.recognitionProvider) {
                ForEach(RecognitionProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isActive)

            if model.recognitionProvider.requiresAudDToken {
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
            if model.recognitionProvider.requiresShazamIO {
                Text("僅限本機開發比較：此 branch 已內嵌 Python、ShazamIO 與 native core；不依賴外部 repo。")
                    .font(.footnote)
                    .foregroundStyle(.orange.opacity(0.90))
                Text(model.shazamIOSetupDescription)
                    .font(.footnote.monospaced())
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.62))
                Button("驗證內嵌 ShazamIO 基線", action: model.testShazamIOEnvironment)
                    .buttonStyle(.bordered)
                    .disabled(model.isActive)
            }
            Divider().overlay(.white.opacity(0.18)).padding(.vertical, 4)
            Label("YouTube 播放設定", systemImage: "play.rectangle.fill")
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                SecureField("貼上 YouTube Data API key", text: $model.youTubeAPIKey)
                    .textFieldStyle(.roundedBorder)
                Button("儲存至 Keychain", action: model.saveYouTubeAPIKey)
                    .buttonStyle(.borderedProminent)
            }
            Text("用於官方 YouTube Data API 搜尋影片；播放器會保持可見以符合嵌入式播放器規範。")
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
                    Label("YouTube 從 \(format(plan.targetOffset)) 開始播放", systemImage: "scope")
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
    }

    @ViewBuilder
    private var youTubePlayerCard: some View {
        if let target = model.youTubeTarget {
            card {
                Label("YouTube 播放中", systemImage: "play.rectangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(target.videoTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(target.channelTitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                YouTubePlayerView(target: target)
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var comparisonCard: some View {
        if let comparison = model.latestComparison {
            card {
                Label("同一段 WAV 的辨識比較", systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                comparisonRow(name: "AudD", result: comparison.audD)
                Divider().overlay(.white.opacity(0.18))
                comparisonRow(name: "ShazamIO", result: comparison.shazamIO)
                Text("比較模式不會自動播放；兩份 JSON log 都在診斷資料夾。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var controlsCard: some View {
        card {
            Toggle("辨識後自動播放 YouTube", isOn: $model.automaticSwitching)
                .foregroundStyle(.white)
            Divider().overlay(.white.opacity(0.18)).padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 8) {
                Text("獨立播放器測試")
                    .foregroundStyle(.white)
                Text("搜尋 Lewis Capaldi 的 \"Wish You The Best\" 並在下方的可見 YouTube 播放器播放；不會使用麥克風或 AudD。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
                Button("測試 YouTube 播放", action: model.testYouTubePlayback)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isActive)
            }
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
        Label("開發診斷啟用時，每輪 10 秒 WAV 與辨識後端回應摘要會保存在本機；可隨時關閉。請勿分享含有店內談話的錄音。", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.62))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func comparisonRow(name: String, result: RecognitionComparison.Result) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(result.displayText)
                .font(.footnote)
                .foregroundStyle(result.song == nil ? .orange : .white.opacity(0.72))
        }
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

private struct YouTubePlayerView: NSViewRepresentable {
    let target: YouTubePlaybackTarget

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedTarget != target else { return }
        context.coordinator.loadedTarget = target
        // YouTube requires WebView clients to identify the embedding app through
        // Referer. Loading local HTML with this base URL gives WKWebView that
        // identity without pretending that YouTube itself is the host page.
        webView.loadHTMLString(playerHTML(for: target), baseURL: URL(string: appOrigin))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedTarget: YouTubePlaybackTarget?
    }

    private var appOrigin: String {
        let identifier = Bundle.main.bundleIdentifier?.lowercased() ?? "com.example.coffeesync"
        return "https://\(identifier)"
    }

    private func playerHTML(for target: YouTubePlaybackTarget) -> String {
        let videoID = javaScriptString(target.videoID)
        let start = String(format: "%.3f", target.startOffset)
        let origin = javaScriptString(appOrigin)
        return """
        <!doctype html><html><body style="margin:0;background:#000">
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        let player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            width: '100%', height: '100%', videoId: \(videoID),
            playerVars: { autoplay: 1, controls: 1, playsinline: 1, rel: 0, start: \(start), origin: \(origin) },
            events: { onReady: function(event) {
              event.target.loadVideoById({videoId: \(videoID), startSeconds: \(start)});
              event.target.playVideo();
            }}
          });
        }
        </script></body></html>
        """
    }

    private func javaScriptString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
