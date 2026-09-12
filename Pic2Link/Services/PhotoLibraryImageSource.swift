import Foundation
import Photos
import UniformTypeIdentifiers

/// Reads the selected asset's current image representation, including edits and
/// iCloud downloads. Live Photo motion uses the existing paired-video path.
enum PhotoLibraryImageSource {
    static func asset(identifier: String) async throws -> PHAsset {
        var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibraryLivePhotoSourceError.accessDenied
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { throw SelectedPhotoError.unavailable }
        guard asset.mediaType == .image else { throw SelectedPhotoError.noPhotos }
        return asset
    }

    static func payload(for asset: PHAsset) async throws -> CaptionUploadPayload {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let originalName = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "photo"
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CaptionUploadPayload, Error>) in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, typeIdentifier, _, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.resume(throwing: CancellationError())
                } else if let data, !data.isEmpty, let typeIdentifier, let type = UTType(typeIdentifier) {
                    continuation.resume(returning: makePayload(data: data, originalName: originalName, type: type))
                } else {
                    continuation.resume(throwing: SelectedPhotoError.unavailable)
                }
            }
        }
    }

    nonisolated static func makePayload(data: Data, originalName: String, type: UTType) -> CaptionUploadPayload {
        let originalType = UTType(filenameExtension: (originalName as NSString).pathExtension)
        let stem = (originalName as NSString).deletingPathExtension
        let fileName = originalType == type ? originalName
            : (stem.isEmpty ? "photo" : stem) + "." + (type.preferredFilenameExtension ?? "jpg")
        return CaptionUploadPayload(data: data, fileName: fileName, mimeType: type.preferredMIMEType ?? "image/jpeg")
    }
}
