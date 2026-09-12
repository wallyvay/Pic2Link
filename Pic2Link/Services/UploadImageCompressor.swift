import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct UploadPixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

struct ImageCompressionProgress: Equatable, Sendable {
    let completedUnits: Int
    let totalUnits: Int

    static let zero = ImageCompressionProgress(completedUnits: 0, totalUnits: 1)

    var fractionCompleted: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1, max(0, Double(completedUnits) / Double(totalUnits)))
    }

    var percentage: Int {
        Int((fractionCompleted * 100).rounded())
    }
}

struct CompressedUploadImage: Equatable, Sendable {
    let data: Data
    let fileName: String?
    let mimeType: String
    let pixelSize: UploadPixelSize
}

enum UploadResizeCalculator {
    nonisolated static func targetSize(
        source: UploadPixelSize,
        settings: UploadCompressionSettings
    ) throws -> UploadPixelSize {
        guard settings.isEnabled else { return source }

        let width = Double(source.width)
        let height = Double(source.height)
        let target: UploadPixelSize

        switch settings.mode {
        case .width:
            let requested = try validDimension(settings.width)
            let scale = Double(requested) / width
            target = UploadPixelSize(width: requested, height: rounded(height * scale))

        case .height:
            let requested = try validDimension(settings.height)
            let scale = Double(requested) / height
            target = UploadPixelSize(width: rounded(width * scale), height: requested)

        case .percentage:
            guard settings.percentage > 0, settings.percentage <= 10_000 else {
                throw ImageCompressionError.invalidPercentage
            }
            let scale = settings.percentage / 100
            target = UploadPixelSize(
                width: rounded(width * scale),
                height: rounded(height * scale)
            )

        case .free:
            target = UploadPixelSize(
                width: try validDimension(settings.width),
                height: try validDimension(settings.height)
            )

        case .maximum:
            let maximumWidth = try validDimension(settings.width)
            let maximumHeight = try validDimension(settings.height)
            let scale = min(
                1,
                min(Double(maximumWidth) / width, Double(maximumHeight) / height)
            )
            target = UploadPixelSize(
                width: rounded(width * scale),
                height: rounded(height * scale)
            )
        }

        guard target.width.multipliedReportingOverflow(by: target.height).overflow == false,
              target.width * target.height <= 100_000_000 else {
            throw ImageCompressionError.outputTooLarge
        }
        return target
    }

    nonisolated private static func validDimension(_ value: Int) throws -> Int {
        guard (1...100_000).contains(value) else {
            throw ImageCompressionError.invalidDimension
        }
        return value
    }

    nonisolated private static func rounded(_ value: Double) -> Int {
        max(1, Int(value.rounded()))
    }
}

struct UploadImageCompressor: Sendable {
    typealias ProgressHandler = @Sendable (ImageCompressionProgress) -> Void

    nonisolated func compress(
        data: Data,
        fileName: String?,
        settings: UploadCompressionSettings,
        onProgress: ProgressHandler = { _ in }
    ) throws -> CompressedUploadImage {
        guard settings.isEnabled else {
            throw ImageCompressionError.disabled
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source) as String? else {
            throw ImageCompressionError.unsupportedImage
        }

        let frameCount = max(1, CGImageSourceGetCount(source))
        let totalUnits = frameCount + 2
        onProgress(ImageCompressionProgress(completedUnits: 0, totalUnits: totalUnits))

        var sourceSizes: [UploadPixelSize] = []
        var targetSizes: [UploadPixelSize] = []
        sourceSizes.reserveCapacity(frameCount)
        targetSizes.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let sourceSize = try pixelSize(of: source, index: index)
            sourceSizes.append(sourceSize)
            targetSizes.append(try UploadResizeCalculator.targetSize(source: sourceSize, settings: settings))
        }
        onProgress(ImageCompressionProgress(completedUnits: 1, totalUnits: totalUnits))

        let type = UTType(sourceType)
        let fileExtension = type?.preferredFilenameExtension ?? "png"
        let mimeType = type?.preferredMIMEType ?? "image/png"
        let resolvedFileName = resolvedFileName(fileName, fileExtension: fileExtension, sourceType: sourceType)

        if zip(sourceSizes, targetSizes).allSatisfy({ source, target in
            source.width == target.width && source.height == target.height
        }) {
            onProgress(ImageCompressionProgress(completedUnits: totalUnits, totalUnits: totalUnits))
            return CompressedUploadImage(
                data: data,
                fileName: resolvedFileName,
                mimeType: mimeType,
                pixelSize: targetSizes[0]
            )
        }

        let supportedTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard supportedTypes.contains(sourceType) else {
            throw ImageCompressionError.unsupportedOutputFormat
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            sourceType as CFString,
            frameCount,
            nil
        ) else {
            throw ImageCompressionError.cannotCreateDestination
        }

        if sourceType == UTType.gif.identifier,
           let globalProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gifProperties = globalProperties[kCGImagePropertyGIFDictionary] {
            CGImageDestinationSetProperties(
                destination,
                [kCGImagePropertyGIFDictionary: gifProperties] as CFDictionary
            )
        }

        for index in 0..<frameCount {
            let targetSize = targetSizes[index]
            let decodedImage = try orientedImage(from: source, index: index, targetSize: targetSize)
            let outputImage = try resized(decodedImage, to: targetSize)
            var properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any] ?? [:]
            properties[kCGImagePropertyOrientation] = 1

            if type?.conforms(to: .jpeg) == true || type?.conforms(to: .heic) == true {
                properties[kCGImageDestinationLossyCompressionQuality] = 0.9
            }

            CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)
            onProgress(ImageCompressionProgress(completedUnits: index + 2, totalUnits: totalUnits))
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressionError.cannotFinalize
        }

        let finalData = outputData as Data
        try validate(finalData, expectedFrames: frameCount, expectedFirstFrameSize: targetSizes[0])
        onProgress(ImageCompressionProgress(completedUnits: totalUnits, totalUnits: totalUnits))

        return CompressedUploadImage(
            data: finalData,
            fileName: resolvedFileName,
            mimeType: mimeType,
            pixelSize: targetSizes[0]
        )
    }

    nonisolated private func pixelSize(of source: CGImageSource, index: Int) throws -> UploadPixelSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw ImageCompressionError.cannotDecode
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            return UploadPixelSize(width: height, height: width)
        }
        return UploadPixelSize(width: width, height: height)
    }

    nonisolated private func orientedImage(
        from source: CGImageSource,
        index: Int,
        targetSize: UploadPixelSize
    ) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetSize.width, targetSize.height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw ImageCompressionError.cannotDecode
        }
        return image
    }

    nonisolated private func resized(_ image: CGImage, to size: UploadPixelSize) throws -> CGImage {
        guard image.width != size.width || image.height != size.height else { return image }

        let colorSpace: CGColorSpace
        if let sourceSpace = image.colorSpace, sourceSpace.model == .rgb {
            colorSpace = sourceSpace
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
            throw ImageCompressionError.cannotCreateCanvas
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let resized = context.makeImage() else {
            throw ImageCompressionError.cannotCreateCanvas
        }
        return resized
    }

    nonisolated private func resolvedFileName(
        _ fileName: String?,
        fileExtension: String,
        sourceType: String
    ) -> String? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let currentExtension = (fileName as NSString).pathExtension
        if let currentType = UTType(filenameExtension: currentExtension),
           currentType.identifier == sourceType {
            return fileName
        }

        let baseName = (fileName as NSString).deletingPathExtension
        return "\(baseName).\(fileExtension)"
    }

    nonisolated private func validate(
        _ data: Data,
        expectedFrames: Int,
        expectedFirstFrameSize: UploadPixelSize
    ) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == expectedFrames,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expectedFirstFrameSize.width,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expectedFirstFrameSize.height,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ImageCompressionError.cannotValidateOutput
        }
    }
}

enum ImageCompressionError: Error, LocalizedError, Equatable {
    case disabled
    case unsupportedImage
    case unsupportedOutputFormat
    case invalidDimension
    case invalidPercentage
    case outputTooLarge
    case cannotDecode
    case cannotCreateCanvas
    case cannotCreateDestination
    case cannotFinalize
    case cannotValidateOutput

    var errorDescription: String? {
        switch self {
        case .disabled:
            return L10n.tr("error.compressionDisabled")
        case .unsupportedImage:
            return L10n.tr("error.compressionUnsupportedImage")
        case .unsupportedOutputFormat:
            return L10n.tr("error.compressionUnsupportedFormat")
        case .invalidDimension:
            return L10n.tr("error.compressionInvalidDimension")
        case .invalidPercentage:
            return L10n.tr("error.compressionInvalidPercentage")
        case .outputTooLarge:
            return L10n.tr("error.compressionOutputTooLarge")
        case .cannotDecode:
            return L10n.tr("error.compressionDecode")
        case .cannotCreateCanvas, .cannotCreateDestination, .cannotFinalize, .cannotValidateOutput:
            return L10n.tr("error.compressionFailed")
        }
    }
}
