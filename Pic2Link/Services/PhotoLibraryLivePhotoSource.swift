import Foundation
import Photos
import UniformTypeIdentifiers

/// The temporary paired-video copy used for one explicit Photos-library upload.
/// The caller owns cleanup; nothing is written back to Photos or saved as a GIF.
struct PhotoLibraryLivePhotoSource: Sendable {
    let pairedVideoURL: URL
    let gifFileName: String
    fileprivate let temporaryDirectory: URL

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

/// Reads only a user-selected Live Photo's paired MOV through PhotoKit.
/// Network access is enabled so iCloud-only originals can be fetched before
/// conversion, while the resulting working copy remains in a unique temp folder.
enum PhotoLibraryLivePhotoSourceResolver {
    static func exportPairedVideo(assetIdentifier: String) async throws -> PhotoLibraryLivePhotoSource {
        let authorization = await ensureReadAuthorization()
        guard authorization == .authorized else {
            throw PhotoLibraryLivePhotoSourceError.accessDenied
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw PhotoLibraryLivePhotoSourceError.assetUnavailable
        }
        guard asset.playbackStyle == .livePhoto else {
            throw PhotoLibraryLivePhotoSourceError.notALivePhoto
        }
        guard let pairedVideo = PHAssetResource.assetResources(for: asset).first(where: {
            $0.type == .pairedVideo
        }) else {
            throw PhotoLibraryLivePhotoSourceError.missingPairedVideo
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pic2Link-LivePhoto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            let videoURL = temporaryDirectory.appendingPathComponent("paired-video.mov")
            try await write(pairedVideo, to: videoURL)
            let originalBaseName = (pairedVideo.originalFilename as NSString).deletingPathExtension
            let gifFileName = "\(originalBaseName.isEmpty ? "live-photo" : originalBaseName).gif"
            return PhotoLibraryLivePhotoSource(
                pairedVideoURL: videoURL,
                gifFileName: gifFileName,
                temporaryDirectory: temporaryDirectory
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func ensureReadAuthorization() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if currentStatus != .notDetermined {
            return currentStatus
        }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    private static func write(_ resource: PHAssetResource, to destinationURL: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: destinationURL,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum PhotoLibraryLivePhotoSourceError: Error, LocalizedError, Equatable {
    case accessDenied
    case assetUnavailable
    case notALivePhoto
    case missingPairedVideo

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return L10n.tr("error.photoLibraryAccess")
        case .assetUnavailable:
            return L10n.tr("error.livePhotoUnavailable")
        case .notALivePhoto:
            return L10n.tr("error.notALivePhoto")
        case .missingPairedVideo:
            return L10n.tr("error.livePhotoGIFSource")
        }
    }
}
