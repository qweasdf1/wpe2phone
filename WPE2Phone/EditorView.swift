import AVFoundation
import AVKit
import SwiftUI

/// Trim a Wallpaper Engine video down to a short segment and convert it into a
/// Live Photo saved to the user's library.
struct EditorView: View {
    let video: ImportedVideo

    @EnvironmentObject private var store: WallpaperStore
    @State private var duration: TimeInterval = 0
    @State private var segmentLength: TimeInterval = 3
    @State private var start: TimeInterval = 0
    @State private var coverTime: TimeInterval = 1.5

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var rebuildTask: Task<Void, Never>?

    @State private var state: ConversionState = .idle
    @State private var resultCover: UIImage?
    @State private var goToGuide = false

    private let lengthChoices: [TimeInterval] = [2, 3, 5]

    enum ConversionState: Equatable {
        case idle, working, done
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                preview
                if state == .idle || isFailed {
                    controls
                }
                statusArea
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(video.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToGuide) {
            GuideView()
        }
        .task { await loadDuration() }
        .onChange(of: start) { _, _ in
            clampCover()
            scheduleRebuild()
        }
        .onChange(of: segmentLength) { _, _ in
            if segmentLength > duration { segmentLength = max(1, duration) }
            start = min(start, maxStart)
            coverTime = start + segmentLength / 2
            scheduleRebuild()
        }
        .onDisappear {
            rebuildTask?.cancel()
            player?.pause()
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9 / 19.5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.card)
                    .aspectRatio(9 / 19.5, contentMode: .fit)
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .frame(maxHeight: 420)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("片段时长", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                Picker("片段时长", selection: $segmentLength) {
                    ForEach(lengthChoices, id: \.self) { len in
                        Text("\(Int(len)) 秒").tag(len)
                    }
                }
                .pickerStyle(.segmented)
                Text("锁屏壁纸建议 2～3 秒，过长容易无法开启动态效果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("起始位置", systemImage: "scissors")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(format(start)) – \(format(start + segmentLength))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $start, in: 0...maxStart, step: 0.1)
                    .tint(Theme.accentA)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("封面帧", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(format(coverTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $coverTime, in: start...(start + segmentLength), step: 0.1)
                    .tint(Theme.accentB)
                Text("封面是锁屏静止时显示的画面，挑最好看的一帧")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await convert() }
            } label: {
                Label("生成实况照片", systemImage: "sparkles")
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(duration <= 0)
        }
        .padding()
        .cardStyle()
    }

    // MARK: Status

    @ViewBuilder
    private var statusArea: some View {
        switch state {
        case .working:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("正在生成实况照片…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .cardStyle()

        case .done:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("已保存到相册「WPE2Phone」")
                    .font(.headline)
                if let resultCover {
                    Image(uiImage: resultCover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button {
                    goToGuide = true
                } label: {
                    Label("下一步：设为锁屏壁纸", systemImage: "iphone")
                }
                .buttonStyle(AccentButtonStyle())
                Button("再转换一段") { state = .idle }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .cardStyle()

        default:
            EmptyView()
        }
    }

    // MARK: Logic

    private var maxStart: TimeInterval {
        max(0, duration - segmentLength)
    }

    private func loadDuration() async {
        let asset = AVURLAsset(url: video.url)
        if let d = try? await asset.load(.duration).seconds, d > 0 {
            duration = d
            if segmentLength > d { segmentLength = max(1, floor(d)) }
            start = 0
            coverTime = segmentLength / 2
        }
        rebuildPlayer()
    }

    private func clampCover() {
        coverTime = min(max(coverTime, start), start + segmentLength)
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run { rebuildPlayer() }
        }
    }

    private func rebuildPlayer() {
        let asset = AVURLAsset(url: video.url)
        guard let track = asset.tracks(withMediaType: .video).first else { return }
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return }
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: segmentLength, preferredTimescale: 600)
        )
        try? compTrack.insertTimeRange(range, of: track, at: .zero)

        let item = AVPlayerItem(asset: composition)
        if let player {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            let newPlayer = AVQueuePlayer()
            newPlayer.isMuted = true
            looper = AVPlayerLooper(player: newPlayer, templateItem: item)
            player = newPlayer
        }
        player?.play()
    }

    private func convert() async {
        state = .working
        player?.pause()
        do {
            let result = try await LivePhotoMaker.make(
                from: video.url,
                segment: .init(start: start, length: segmentLength, coverTime: coverTime)
            )
            try await store.save(photoData: result.photoData, videoURL: result.videoURL)
            resultCover = result.coverImage
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
            player?.play()
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }
}
