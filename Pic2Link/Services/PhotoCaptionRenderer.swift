import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import WMMarkCore
import WMMarkRenderer

enum PhotoCaptionError: LocalizedError {
    case emptyText, unreadableImage, unsupportedAnimation, imageTooLarge, textDoesNotFit, encodingFailed

    nonisolated var errorDescription: String? {
        switch self {
        case .emptyText: return L10n.tr("caption.error.empty")
        case .unreadableImage: return L10n.tr("caption.error.image")
        case .unsupportedAnimation: return L10n.tr("caption.error.animation")
        case .imageTooLarge: return L10n.tr("caption.error.size")
        case .textDoesNotFit: return L10n.tr("caption.error.fit")
        case .encodingFailed: return L10n.tr("caption.error.encode")
        }
    }
}

/// A native macOS adapter around Fluffmark's public theme, layout and rendering APIs.
/// No App launch, files, font downloads, or network requests are involved.
struct PhotoCaptionRenderer: Sendable {
    nonisolated init() {}
    nonisolated func compose(_ input: CaptionUploadPayload, text: String) throws -> CaptionUploadPayload {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PhotoCaptionError.emptyText
        }
        guard text.utf16.count <= 4_000 else { throw PhotoCaptionError.textDoesNotFit }
        guard let source = CGImageSourceCreateWithData(input.data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else {
            throw PhotoCaptionError.unreadableImage
        }
        let count = CGImageSourceGetCount(source)
        let isGIF = type == UTType.gif.identifier
        guard count > 0 else { throw PhotoCaptionError.unreadableImage }
        // Never silently flatten animations or multi-page sources.
        guard count == 1 || isGIF else { throw PhotoCaptionError.unsupportedAnimation }
        guard count <= 600 else { throw PhotoCaptionError.imageTooLarge }
        var totalPixels = 0
        for index in 0..<count {
            let dimensions = try sourceDimensions(source, index: index)
            guard dimensions.width <= 16_384, dimensions.height <= 16_384,
                  dimensions.width * dimensions.height <= 40_000_000 else {
                throw PhotoCaptionError.imageTooLarge
            }
            totalPixels += dimensions.width * dimensions.height
            guard totalPixels <= 200_000_000 else { throw PhotoCaptionError.imageTooLarge }
        }

        let first = try orientedImage(source, index: 0)
        let document = try recommendedDocument(image: first, text: text)
        let renderer = WMStaticRenderer()
        let output = NSMutableData()
        let outputType = isGIF ? UTType.gif : .png
        guard let destination = CGImageDestinationCreateWithData(
            output, outputType.identifier as CFString, count, nil
        ) else { throw PhotoCaptionError.encodingFailed }
        if isGIF,
           let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gifProperties = properties[kCGImagePropertyGIFDictionary] {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: gifProperties] as CFDictionary)
        }
        for index in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                let frame = index == 0 ? first : try orientedImage(source, index: index)
                guard frame.width == first.width, frame.height == first.height else {
                    throw PhotoCaptionError.unsupportedAnimation
                }
                let rendered = try renderer.render(source: frame, document: document)
                var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
                if isGIF,
                   let original = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                   let timing = original[kCGImagePropertyGIFDictionary] {
                    properties[kCGImagePropertyGIFDictionary] = timing
                }
                CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination),
              let check = CGImageSourceCreateWithData(output, nil),
              CGImageSourceGetCount(check) == count else { throw PhotoCaptionError.encodingFailed }
        let stem = input.fileName.map { ($0 as NSString).deletingPathExtension } ?? "image"
        return CaptionUploadPayload(
            data: output as Data,
            fileName: stem + "-caption." + (isGIF ? "gif" : "png"),
            mimeType: isGIF ? "image/gif" : "image/png"
        )
    }

    nonisolated func recommendedDocument(image: CGImage, text: String) throws -> WMDocument {
        let analysis = WMTextSourceAnalyzer.analyze(image)
        let templates = analysis.photoTheme.artTemplates(basedOn: WMTextStyle())
        guard let template = templates.first(where: { $0.direction == .editorial }) else {
            throw PhotoCaptionError.textDoesNotFit
        }
        var document = WMDocument(canvasPixelSize: WMSize(width: Double(image.width), height: Double(image.height)))
        let element = WMElement(content: .text(WMTextAnnotation(
            text: text,
            bounds: WMRect(x: 0.2, y: 0.4, width: 0.6, height: 0.2),
            style: template.style,
            isAutoLayoutEnabled: true,
            artDirection: template.direction
        )))
        guard let candidate = WMTextAutoLayoutEngine.layoutCandidates(
            for: element,
            in: document,
            subjectMask: subjectMask(image),
            readabilityMap: analysis.sceneAnalysis.readabilityMap,
            limit: 1
        ).first else { throw PhotoCaptionError.textDoesNotFit }
        document.elements = [candidate.element]
        return document
    }

    nonisolated private func sourceDimensions(_ source: CGImageSource, index: Int) throws -> UploadPixelSize {
        guard let p = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int,
              let h = p[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 16_384, h <= 16_384 else { throw PhotoCaptionError.imageTooLarge }
        return UploadPixelSize(width: w, height: h)
    }

    nonisolated private func orientedImage(_ source: CGImageSource, index: Int) throws -> CGImage {
        let size = try sourceDimensions(source, index: index)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw PhotoCaptionError.unreadableImage }
        return image
    }

    nonisolated private func subjectMask(_ image: CGImage) -> WMSubjectMask {
        // Vision is a platform adapter here; candidate scoring stays in the shared WMMark engine.
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        if (try? handler.perform([foreground])) != nil,
           let result = foreground.results?.first, !result.allInstances.isEmpty,
           let buffer = try? result.generateMask(forInstances: result.allInstances) {
            return compactMask(buffer)
        }
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        if (try? handler.perform([saliency])) != nil, let buffer = saliency.results?.first?.pixelBuffer {
            return compactMask(buffer).dilated(radius: 2)
        }
        return .empty
    }

    nonisolated func compactMask(_ buffer: CVPixelBuffer) -> WMSubjectMask {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return .empty }
        let sourceWidth = CVPixelBufferGetWidth(buffer)
        let sourceHeight = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard sourceWidth > 0, sourceHeight > 0,
              format == kCVPixelFormatType_OneComponent8 || format == kCVPixelFormatType_OneComponent32Float else {
            return .empty
        }
        let scale = min(1, 192 / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var values = [UInt8](repeating: 0, count: width * height)
        // Vision pixel-buffer rows already use the top-left convention expected by WMMark.
        // Max pooling preserves thin foreground details when compacting the mask.
        for y in 0..<sourceHeight {
            let row = base.advanced(by: y * stride)
            let targetRow = min(height - 1, y * height / sourceHeight) * width
            for x in 0..<sourceWidth {
                let value: UInt8
                if format == kCVPixelFormatType_OneComponent8 {
                    value = row.assumingMemoryBound(to: UInt8.self)[x]
                } else {
                    let sample = row.assumingMemoryBound(to: Float.self)[x]
                    value = sample.isFinite ? UInt8(max(0, min(255, sample * 255))) : 0
                }
                let index = targetRow + min(width - 1, x * width / sourceWidth)
                values[index] = max(values[index], value)
            }
        }
        return WMSubjectMask(width: width, height: height, values: values)
    }
}
