import Photos
import SwiftUI
import UIKit

/// Tracks the app's own Photos album ("WPE2Phone"), saves generated Live Photos into it,
/// and exposes thumbnails for the home-screen grid.
@MainActor
final class WallpaperStore: ObservableObject {
    static let albumName = "WPE2Phone"

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var authorization: PHAuthorizationStatus

    private let imageManager = PHCachingImageManager()

    init() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    // MARK: Authorization

    func ensureAddAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        authorization = status
        return status == .authorized || status == .limited
    }

    // MARK: Saving

    /// Saves the generated Live Photo pair and files it into the app album.
    func save(photoData: Data, videoURL: URL) async throws {
        guard await ensureAddAccess() else {
            throw LivePhotoError.photoSaveFailed("没有相册写入权限，请在系统设置中允许")
        }

        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photoData, options: nil)
            let videoOptions = PHAssetResourceCreationOptions()
            videoOptions.shouldMoveFile = false
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
            placeholderID = request.placeholderForCreatedAsset?.localIdentifier
        }

        if let placeholderID {
            try? await addToAlbum(assetLocalID: placeholderID)
        }
        try? FileManager.default.removeItem(at: videoURL)
        refresh()
    }

    private func addToAlbum(assetLocalID: String) async throws {
        let collection = fetchAlbum() ?? (try await createAlbum())
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetLocalID], options: nil
        ).firstObject else { return }

        try await PHPhotoLibrary.shared().performChanges {
            guard let change = PHAssetCollectionChangeRequest(for: collection) else { return }
            change.addAssets([asset] as NSArray)
        }
    }

    private func fetchAlbum() -> PHAssetCollection? {
        let result = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular,
            options: {
                let o = PHFetchOptions()
                o.predicate = NSPredicate(format: "localizedTitle = %@", Self.albumName)
                return o
            }()
        )
        return result.firstObject
    }

    private func createAlbum() async throws -> PHAssetCollection {
        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            placeholderID = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: Self.albumName)
                .placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let placeholderID,
              let collection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [placeholderID], options: nil
              ).firstObject else {
            throw LivePhotoError.photoSaveFailed("无法创建相册 \(Self.albumName)")
        }
        return collection
    }

    // MARK: Listing

    func refresh() {
        guard let album = fetchAlbum() else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: album, options: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
    }

    func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            imageManager.requestImage(
                for: asset, targetSize: targetSize,
                contentMode: .aspectFill, options: options
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }
}
