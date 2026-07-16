import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var model = CoffeeSessionViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.13), Color(red: 0.14, green: 0.11, blue: 0.19)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    configurationCard
                    statusCard
                    recognitionCard
                    playerCard
                    controlsCard
                    privacyNote
                }
                .frame(maxWidth: 620)
                .padding(28)
            }
        }
        .frame(minWidth: 600, minHeight: 700)
        .tint(.blue)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
                .background(.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("CoffeeSync")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("ShazamIO 辨識，YouTube Music 曲庫選歌後播放。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
            Spacer()
            Text(model.isActive ? "同步中" : "待命")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.isActive ? .green : .white.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.10), in: Capsule())
        }
    }

    private var configurationCard: some View {
        card {
            Label("YouTube Music 歌曲解析（實驗）", systemImage: "music.note.list")
                .font(.headline)
                .foregroundStyle(.white)
            Text("先從 YouTube Music 的 songs 曲庫選擇標準發行版本，再交給可見的 YouTube 播放器對時。")
                .foregroundStyle(.white.opacity(0.78))
            Text("此測試分支不需要 YouTube Data API key；ytmusicapi 是非官方曲庫解析器，服務端改版時可能需要更新。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var statusCard: some View {
        card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.phase.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(model.statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.70))
                }
                Spacer()
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label(model.nextRecognitionMessage(at: context.date), systemImage: "clock.arrow.circlepath")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
            }
            HStack(spacing: 10) {
                Button(action: model.toggleSession) {
                    Label(model.isActive ? "停止同步" : "開始同步", systemImage: model.isActive ? "stop.fill" : "waveform")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isActive ? .red : .blue)
                if model.isActive {
                    Button("Re-sync", systemImage: "arrow.clockwise", action: model.resyncNow)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
        }
    }

    @ViewBuilder
    private var recognitionCard: some View {
        if let song = model.lastRecognition {
            card {
                Label("最近辨識", systemImage: "music.note.list")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(song.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(song.artist)
                    .foregroundStyle(.white.opacity(0.72))
                if let plan = model.currentPlan {
                    Divider().overlay(.white.opacity(0.16)).padding(.vertical, 2)
                    Label("YouTube 將從 \(format(plan.targetOffset)) 開始", systemImage: "scope")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
        }
    }

    @ViewBuilder
    private var playerCard: some View {
        if let target = model.youTubeTarget {
            card {
                Label("YouTube 播放器", systemImage: "play.rectangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(target.videoTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(target.channelTitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
                YouTubePlayerView(
                    target: target,
                    seekCommand: model.playbackSeekCommand,
                    onPlaybackEnded: model.playerDidFinish
                )
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var controlsCard: some View {
        card {
            Toggle("辨識後自動播放 YouTube", isOn: $model.automaticSwitching)
                .foregroundStyle(.white)
            Divider().overlay(.white.opacity(0.16)).padding(.vertical, 3)
            VStack(alignment: .leading, spacing: 8) {
                Text("環境音錄音長度").foregroundStyle(.white)
                Picker("錄音長度", selection: $model.captureDuration) {
                    ForEach(CaptureDurationOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isActive)
                Text("ShazamIO 建議從 10 秒開始；錄音長度也會計入初始對時位置。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Divider().overlay(.white.opacity(0.16)).padding(.vertical, 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("額外播放延遲").foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "+%.2fs", model.latencyAdjustment))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
                Slider(value: $model.latencyAdjustment, in: 0...15, step: 0.25)
                Text("調整時會立即移動目前影片的播放位置。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
            HStack {
                Button("測試 YouTube 播放", action: model.testYouTubePlayback)
                    .buttonStyle(.bordered)
                    .disabled(model.isActive)
            }
        }
    }

    private var privacyNote: some View {
        Label("CoffeeSync 只在同步期間錄製短片段。請先取得所在地要求的錄音同意，並自行遵守 YouTube、ytmusicapi 與第三方服務條款。", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.60))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusIcon: String {
        switch model.phase {
        case .idle: "waveform"
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
    let seekCommand: YouTubeSeekCommand?
    let onPlaybackEnded: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "coffeeSync")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedTarget != target {
            context.coordinator.loadedTarget = target
            context.coordinator.isLoadingTarget = true
            webView.loadHTMLString(playerHTML(for: target), baseURL: URL(string: appOrigin))
        }
        guard let seekCommand, context.coordinator.lastSeekCommandID != seekCommand.id else { return }
        context.coordinator.lastSeekCommandID = seekCommand.id
        context.coordinator.queueSeek(seekCommand.delta, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator _: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "coffeeSync")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedTarget: YouTubePlaybackTarget?
        var lastSeekCommandID: UUID?
        var isLoadingTarget = false
        private var pendingSeekDelta: TimeInterval = 0
        var onPlaybackEnded: (() -> Void)?

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            isLoadingTarget = false
            applyPendingSeek(in: webView)
        }

        func queueSeek(_ delta: TimeInterval, in webView: WKWebView) {
            pendingSeekDelta += delta
            applyPendingSeek(in: webView)
        }

        private func applyPendingSeek(in webView: WKWebView) {
            guard !isLoadingTarget, abs(pendingSeekDelta) >= 0.001 else { return }
            let delta = pendingSeekDelta
            pendingSeekDelta = 0
            let javaScriptDelta = String(format: "%.3f", delta)
            webView.evaluateJavaScript("window.coffeeSyncSeekRelative && window.coffeeSyncSeekRelative(\(javaScriptDelta));")
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "coffeeSync", message.body as? String == "ended" else { return }
            DispatchQueue.main.async { [weak self] in self?.onPlaybackEnded?() }
        }
    }

    private var appOrigin: String {
        let identifier = Bundle.main.bundleIdentifier?.lowercased() ?? "com.example.coffeesync"
        return "https://\(identifier)"
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onPlaybackEnded = onPlaybackEnded
        return coordinator
    }

    private func playerHTML(for target: YouTubePlaybackTarget) -> String {
        let videoID = javaScriptString(target.videoID)
        let start = String(format: "%.3f", target.startOffset)
        let origin = javaScriptString(appOrigin)
        return """
        <!doctype html><html><body style="margin:0;background:#000"><div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script><script>
        let pendingSeekDeltas = [];
        let applySeek = function(delta) {
          if (!window.coffeeSyncPlayer || !window.coffeeSyncPlayer.getCurrentTime) {
            pendingSeekDeltas.push(delta); return;
          }
          const next = Math.max(0, window.coffeeSyncPlayer.getCurrentTime() + delta);
          window.coffeeSyncPlayer.seekTo(next, true);
          window.coffeeSyncPlayer.playVideo();
        };
        window.coffeeSyncSeekRelative = applySeek;
        function onYouTubeIframeAPIReady() {
          window.coffeeSyncPlayer = new YT.Player('player', { width: '100%', height: '100%', videoId: \(videoID),
            playerVars: { autoplay: 1, controls: 1, playsinline: 1, rel: 0, start: \(start), origin: \(origin) },
            events: { onReady: function(event) {
              event.target.loadVideoById({videoId: \(videoID), startSeconds: \(start)});
              event.target.playVideo();
              while (pendingSeekDeltas.length > 0) { applySeek(pendingSeekDeltas.shift()); }
            }, onStateChange: function(event) {
              if (event.data === YT.PlayerState.ENDED) {
                window.webkit.messageHandlers.coffeeSync.postMessage('ended');
              }
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
