import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A video the user picked for conversion, either from Files or from Photos.
struct ImportedVideo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
}

/// Copies a Photos-selected video into a temp file AVFoundation can read.
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { transferable in
            SentTransferredFile(transferable.url)
        } importing: { received in
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("wpe_import_\(UUID().uuidString).mov")
            if FileManager.default.fileExists(atPath: temp.path) {
                try FileManager.default.removeItem(at: temp)
            }
            try FileManager.default.copyItem(at: received.file, to: temp)
            return VideoTransferable(url: temp)
        }
    }
}
