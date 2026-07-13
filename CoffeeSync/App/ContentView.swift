import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var model = CoffeeSessionViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.13, green: 0.08, blue: 0.06), Color(red: 0.31, green: 0.18, blue: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        header
                        sessionButton
                        statusCard
                        playbackCard
                        controlsCard
                        privacyNote
                    }
                    .padding(20)
                }
            }
            .navigationTitle("CoffeeSync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(.orange)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("把咖啡廳的音樂，留在耳機裡")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("自動辨識店內歌曲，從接近現場進度的時間點播放。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var sessionButton: some View {
        Button(action: model.toggleSession) {
            VStack(spacing: 10) {
                Image(systemName: model.isActive ? "stop.fill" : "waveform")
                    .font(.system(size: 34, weight: .semibold))
                Text(model.isActive ? "結束咖啡工作階段" : "開始咖啡工作階段")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .foregroundStyle(.white)
            .background(model.isActive ? Color.red.opacity(0.86) : Color.orange.opacity(0.86), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityHint("會要求麥克風及 Apple Music 權限")
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
                    Text(model.statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
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
                    .padding(.top, 4)
                Text(song.artist)
                    .foregroundStyle(.white.opacity(0.72))
                if let plan = model.currentPlan {
                    Divider().overlay(.white.opacity(0.18)).padding(.vertical, 4)
                    Label("耳機從 \(format(plan.targetOffset)) 開始播放", systemImage: "scope")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
    }

    private var controlsCard: some View {
        card {
            Toggle("辨識後自動切換 Apple Music", isOn: $model.automaticSwitching)
                .foregroundStyle(.white)
            Divider().overlay(.white.opacity(0.18)).padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("耳機延遲微調")
                    Spacer()
                    Text(String(format: "+%.2fs", model.latencyAdjustment))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                .foregroundStyle(.white)
                Slider(value: $model.latencyAdjustment, in: 0...1.5, step: 0.05)
            }
        }
    }

    private var privacyNote: some View {
        Label("僅在你手動開始工作階段時使用麥克風。CoffeeSync 不保存錄音，只將音訊交給 ShazamKit 產生比對。", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statusIcon: String {
        switch model.phase {
        case .idle: "cup.and.saucer"
        case .needsHeadphones: "headphones"
        case .requestingPermissions: "lock.shield"
        case .listening: "waveform"
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
