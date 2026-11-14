import AVFoundation
import CoreImage
import ImageIO
import Photos
import UIKit

/// Errors surfaced by the Live Photo pipeline.
enum LivePhotoError: LocalizedError {
    case noVideoTrack
    case cannotCreateReader
    case cannotCreateWriter
    case writerFailed(String)
    case stillImageFailed
    case photoSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "这个文件里没有可用的视频轨道"
        case .cannotCreateReader: return "无法读取视频内容"
        case .cannotCreateWriter: return "无法创建实况照片视频"
        case .writerFailed(let msg): return "写入失败：\(msg)"
        case .stillImageFailed: return "无法提取封面帧"
        case .photoSaveFailed(let msg): return "保存到相册失败：\(msg)"
        }
    }
}

/// Converts a segment of a Wallpaper Engine video into an iOS-compatible Live Photo
/// (a JPEG still + MOV pair sharing one asset identifier), ready to be saved to Photos.
struct LivePhotoMaker {

    struct Segment {
        var start: TimeInterval
        var length: TimeInterval
        /// Absolute time in the source video used for the still cover frame.
        var coverTime: TimeInterval
    }

    struct Result {
        var photoData: Data
        var videoURL: URL
        var coverImage: UIImage
    }

    /// Long edge is capped so the Live Photo stays within Photos' wallpaper limits.
    static let maxOutputDimension: CGFloat = 1920

    static func make(from sourceURL: URL, segment: Segment) async throws -> Result {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LivePhotoError.noVideoTrack
        }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw LivePhotoError.cannotCreateReader }

        let duration = try await asset.load(.duration).seconds
        let start = max(0, min(segment.start, max(0, duration - 0.5)))
        let length = max(0.5, min(segment.length, duration - start))
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        try compTrack.insertTimeRange(range, of: track, at: .zero)

        let assetID = UUID().uuidString
        let outputSize = try await scaledOutputSize(for: track)
        let movURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wpe_\(assetID).mov")

        try await writeVideo(composition: composition,
                             videoTrack: compTrack,
                             outputSize: outputSize,
                             assetID: assetID,
                             to: movURL)

        let cover = CMTime(seconds: max(start, min(segment.coverTime, start + length)),
                           preferredTimescale: 600)
        let still = try await makeStill(asset: asset,
                                        at: cover,
                                        assetID: assetID,
                                        maxDimension: maxOutputDimension)
        guard let coverImage = UIImage(data: still) else { throw LivePhotoError.stillImageFailed }

        return Result(photoData: still, videoURL: movURL, coverImage: coverImage)
    }

    // MARK: - Private

    private static func scaledOutputSize(for track: AVAssetTrack) async throws -> CGSize {
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let size = natural.applying(transform)
        let w = abs(size.width), h = abs(size.height)
        let longEdge = max(w, h)
        guard longEdge > maxOutputDimension else {
            return CGSize(width: even(w), height: even(h))
        }
        let scale = maxOutputDimension / longEdge
        return CGSize(width: even(w * scale), height: even(h * scale))
    }

    private static func even(_ value: CGFloat) -> Int {
        Int(value) - Int(value) % 2
    }

    /// Re-encodes the trimmed composition to H.264 MOV and injects the
    /// `com.apple.quicktime.content.identifier` metadata that pairs it with the still.
    private static func writeVideo(composition: AVComposition,
                                   videoTrack: AVAssetTrack,
                                   outputSize: CGSize,
                                   assetID: String,
                                   to outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        guard let reader = try? AVAssetReader(asset: composition) else {
            throw LivePhotoError.cannotCreateReader
        }
        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        guard reader.canAdd(readerOutput) else { throw LivePhotoError.cannotCreateReader }
        reader.add(readerOutput)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            throw LivePhotoError.cannotCreateWriter
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw LivePhotoError.cannotCreateWriter }
        writer.add(videoInput)

        // Live Photo pairing metadata track.
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.content.identifier",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                "com.apple.metadata.datatype.UTF-8"
        ]
        var formatDescription: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray,
            formatDescriptionOut: &formatDescription
        )
        let metadataInput = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        metadataInput.expectsMediaDataInRealTime = false
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        if writer.canAdd(metadataInput) {
            writer.add(metadataInput)
        }

        guard reader.startReading(), writer.startWriting() else {
            throw LivePhotoError.writerFailed(writer.error?.localizedDescription ?? "启动失败")
        }
        writer.startSession(atSourceTime: .zero)

        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataContentIdentifier
        item.value = assetID as NSString
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        metadataAdaptor.append(AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(start: .zero, duration: .invalid)
        ))

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "wpe2phone.writer")
            var resumed = false
            let lock = NSLock()
            func finish(_ result: Swift.Result<Void, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        if !videoInput.append(sample) {
                            finish(.failure(LivePhotoError.writerFailed(
                                writer.error?.localizedDescription ?? "写入样本失败")))
                            return
                        }
                    } else {
                        videoInput.markAsFinished()
                        if let error = reader.error {
                            finish(.failure(error))
                            return
                        }
                        writer.finishWriting {
                            if writer.status == .completed {
                                finish(.success(()))
                            } else {
                                finish(.failure(LivePhotoError.writerFailed(
                                    writer.error?.localizedDescription ?? "完成写入失败")))
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    /// Renders one frame and stamps it with the Apple maker note ("17" = asset identifier)
    /// so Photos recognises the JPEG + MOV pair as one Live Photo.
    private static func makeStill(asset: AVAsset,
                                  at time: CMTime,
                                  assetID: String,
                                  maxDimension: CGFloat) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .init(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = .init(seconds: 0.1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        let cgImage = try await generator.image(at: time).image

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.jpeg" as CFString, 1, nil
        ) else { throw LivePhotoError.stillImageFailed }

        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": assetID]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoError.stillImageFailed
        }
        return data as Data
    }
}
