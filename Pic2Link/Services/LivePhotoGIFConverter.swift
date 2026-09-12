import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A verified image/video pair copied to the clipboard from a Live Photo.
///
/// We deliberately require the public Live Photo content identifier in both
/// resources. This prevents a still image placed beside an unrelated movie on
/// the clipboard from being converted as if it were a Live Photo.
struct ClipboardLivePhotoSource: Equatable, Sendable {
    let stillImageURL: URL
    let pairedVideoURL: URL

    nonisolated var gifFileName: String {
        let baseName = (stillImageURL.lastPathComponent as NSString).deletingPathExtension
        return "\(baseName.isEmpty ? "live-photo" : baseName).gif"
    }
}

enum ClipboardLivePhotoResolver {
    static func firstSource(in pasteboard: NSPasteboard) async -> ClipboardLivePhotoSource? {
        let fileURLs = PasteboardFileResolver.fileURLs(in: pasteboard)
        let imageURLs = fileURLs.filter(PasteboardFileResolver.isImageFile)
        let videoURLs = fileURLs.filter(isVideoFile)

        for videoURL in videoURLs {
            guard let videoIdentifier = await contentIdentifier(inVideoAt: videoURL) else { continue }

            for imageURL in imageURLs where contentIdentifier(inImageAt: imageURL) == videoIdentifier {
                return ClipboardLivePhotoSource(
                    stillImageURL: imageURL,
                    pairedVideoURL: videoURL
                )
            }
        }

        return nil
    }

    nonisolated private static func isVideoFile(_ fileURL: URL) -> Bool {
        let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        guard values?.isDirectory != true else { return false }

        let contentType = values?.contentType ?? UTType(filenameExtension: fileURL.pathExtension)
        return contentType?.conforms(to: .movie) ?? false
    }

    private static func contentIdentifier(inImageAt imageURL: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [AnyHashable: Any] else {
            return nil
        }

        for (key, value) in makerApple where String(describing: key) == "17" {
            if let value = value as? String, !value.isEmpty {
                return value
            }
            if let value = value as? NSString, value.length > 0 {
                return value as String
            }
        }
        return nil
    }

    private static func contentIdentifier(inVideoAt videoURL: URL) async -> String? {
        let asset = AVURLAsset(url: videoURL)
        guard let metadata = try? await asset.load(.metadata),
              let item = metadata.first(where: {
                  $0.identifier == .quickTimeMetadataContentIdentifier
              }) else {
            return nil
        }
        return try? await item.load(.stringValue)
    }
}

/// Converts only the paired video portion of a verified Live Photo to a GIF.
/// The GIF is returned as Data and never written to disk.
struct LivePhotoGIFConverter: Sendable {
    nonisolated static let targetShortSide = 480
    nonisolated static let framesPerSecond = 10
    nonisolated static let maximumFrameCount = 120

    typealias ProgressHandler = @Sendable (ImageCompressionProgress) -> Void

    nonisolated func convert(
        pairedVideoURL: URL,
        fileName: String,
        onProgress: ProgressHandler = { _ in }
    ) async throws -> CompressedUploadImage {
        let asset = AVURLAsset(url: pairedVideoURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw LivePhotoGIFConversionError.missingPairedVideo
        }

        let durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw LivePhotoGIFConversionError.invalidVideo
        }

        let sourceSize = try await displaySize(for: videoTrack)
        let targetSize = Self.targetSize(for: sourceSize)
        let frameCount = min(
            Self.maximumFrameCount,
            max(1, Int((durationSeconds * Double(Self.framesPerSecond)).rounded(.up)))
        )
        let totalUnits = frameCount + 1
        onProgress(ImageCompressionProgress(completedUnits: 0, totalUnits: totalUnits))

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw LivePhotoGIFConversionError.cannotCreateGIF
        }

        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetSize.width, height: targetSize.height)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let frameDelay = durationSeconds / Double(frameCount)
        for index in 0..<frameCount {
            let requestedSeconds = min(
                durationSeconds - (1 / Double(Self.framesPerSecond * 10)),
                Double(index) / Double(Self.framesPerSecond)
            )
            let requestedTime = CMTime(seconds: max(0, requestedSeconds), preferredTimescale: 600)
            let image: CGImage
            do {
                image = try generator.copyCGImage(at: requestedTime, actualTime: nil)
            } catch {
                throw LivePhotoGIFConversionError.cannotReadVideoFrame
            }

            let resizedImage = try resized(image, to: targetSize)
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frameDelay,
                    kCGImagePropertyGIFUnclampedDelayTime: frameDelay
                ]
            ]
            CGImageDestinationAddImage(destination, resizedImage, frameProperties as CFDictionary)
            onProgress(ImageCompressionProgress(completedUnits: index + 1, totalUnits: totalUnits))
        }

        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoGIFConversionError.cannotCreateGIF
        }

        let gifData = outputData as Data
        try validate(gifData, expectedFrameCount: frameCount, expectedSize: targetSize)
        onProgress(ImageCompressionProgress(completedUnits: totalUnits, totalUnits: totalUnits))

        return CompressedUploadImage(
            data: gifData,
            fileName: fileName,
            mimeType: "image/gif",
            pixelSize: targetSize
        )
    }

    nonisolated static func targetSize(for sourceSize: UploadPixelSize) -> UploadPixelSize {
        let shortestSide = min(sourceSize.width, sourceSize.height)
        guard shortestSide > 0 else { return sourceSize }

        let scale = min(1, Double(targetShortSide) / Double(shortestSide))
        return UploadPixelSize(
            width: max(1, Int((Double(sourceSize.width) * scale).rounded())),
            height: max(1, Int((Double(sourceSize.height) * scale).rounded()))
        )
    }

    nonisolated private func displaySize(for track: AVAssetTrack) async throws -> UploadPixelSize {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(preferredTransform)
        return UploadPixelSize(
            width: max(1, Int(abs(transformed.width).rounded())),
            height: max(1, Int(abs(transformed.height).rounded()))
        )
    }

    nonisolated private func resized(_ image: CGImage, to size: UploadPixelSize) throws -> CGImage {
        guard image.width != size.width || image.height != size.height else { return image }

        let colorSpace: CGColorSpace
        if let sourceColorSpace = image.colorSpace, sourceColorSpace.model == .rgb {
            colorSpace = sourceColorSpace
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LivePhotoGIFConversionError.cannotCreateGIF
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let output = context.makeImage() else {
            throw LivePhotoGIFConversionError.cannotCreateGIF
        }
        return output
    }

    nonisolated private func validate(
        _ data: Data,
        expectedFrameCount: Int,
        expectedSize: UploadPixelSize
    ) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              typeIdentifier == UTType.gif.identifier,
              CGImageSourceGetCount(source) == expectedFrameCount,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expectedSize.width,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expectedSize.height else {
            throw LivePhotoGIFConversionError.cannotCreateGIF
        }
    }
}

enum LivePhotoGIFConversionError: Error, LocalizedError, Equatable {
    case missingPairedVideo
    case invalidVideo
    case cannotReadVideoFrame
    case cannotCreateGIF

    var errorDescription: String? {
        switch self {
        case .missingPairedVideo:
            return L10n.tr("error.livePhotoGIFSource")
        case .invalidVideo, .cannotReadVideoFrame, .cannotCreateGIF:
            return L10n.tr("error.livePhotoGIFConversion")
        }
    }
}
