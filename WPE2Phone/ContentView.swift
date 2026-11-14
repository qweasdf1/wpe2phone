import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: WallpaperStore

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false
    @State private var selectedVideo: ImportedVideo?
    @State private var importError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    stepOne
                    stepTwo
                    stepThree
                    library
                }
                .padding()
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("WPE2Phone")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedVideo) { video in
                EditorView(video: video)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task { await handlePhotoPick(item) }
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .onAppear { store.refresh() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Theme.accentGradient,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Wallpaper Engine → iPhone")
                .font(.title2.bold())
            Text("把电脑上的视频壁纸变成 iPhone 锁屏实况照片")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Steps

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StepBadge(number: 1)
                Text("在电脑上提取壁纸")
                    .font(.headline)
            }
            Text("运行随附的 wpe_extract.py 脚本，它会自动扫描 Wallpaper Engine 创意工坊目录，把视频壁纸转成 iPhone 可用的 MP4。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("再用隔空投送或数据线把 MP4 传到 iPhone", systemImage: "airplayaudio")
                .font(.footnote)
                .foregroundStyle(Theme.accentA)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StepBadge(number: 2)
                Text("导入视频并转换")
                    .font(.headline)
            }
            HStack(spacing: 12) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("从文件导入", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accentA)

                Button {
                    showPhotosPicker = true
                } label: {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accentB)
            }
            Text("支持 MP4 / MOV；WebM 请先用电脑端脚本转码")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
        .photosPicker(isPresented: $showPhotosPicker,
                      selection: $photoPickerItem,
                      matching: .videos)
    }

    private var stepThree: some View {
        NavigationLink {
            GuideView()
        } label: {
            HStack(spacing: 12) {
                StepBadge(number: 3)
                Text("设为锁屏动态壁纸")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .cardStyle()
            .foregroundStyle(.white)
        }
    }

    // MARK: Library

    @ViewBuilder
    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已转换的壁纸")
                    .font(.headline)
                Spacer()
                if !store.assets.isEmpty {
                    Text("\(store.assets.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if store.assets.isEmpty {
                Label("还没有转换记录，先导入一段壁纸视频吧",
                      systemImage: "photo.stack")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.assets, id: \.localIdentifier) { asset in
                        WallpaperCell(asset: asset)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }

    // MARK: Import handling

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("wpe_file_\(UUID().uuidString).mp4")
                if FileManager.default.fileExists(atPath: temp.path) {
                    try FileManager.default.removeItem(at: temp)
                }
                try FileManager.default.copyItem(at: url, to: temp)
                selectedVideo = ImportedVideo(
                    url: temp,
                    name: url.deletingPathExtension().lastPathComponent
                )
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        defer { photoPickerItem = nil }
        do {
            if let movie = try await item.loadTransferable(type: VideoTransferable.self) {
                selectedVideo = ImportedVideo(
                    url: movie.url,
                    name: item.itemIdentifier ?? "相册视频"
                )
            } else {
                importError = "无法读取这个视频"
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// One converted wallpaper thumbnail with a Live Photo badge.
private struct WallpaperCell: View {
    let asset: PHAsset
    @EnvironmentObject private var store: WallpaperStore
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.card
                        .overlay { ProgressView().tint(.white) }
                }
            }
            .aspectRatio(9 / 19.5, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Image(systemName: "livephoto")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.45), in: Circle())
                .padding(6)
        }
        .task {
            let size = CGSize(width: 240, height: 520)
            image = await store.thumbnail(for: asset, targetSize: size)
        }
    }
}
