import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pic2Link

final class CaptionUploadTests: XCTestCase {
    func testVisionMaskRetainsTopLeftOrientation() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 4, 2, kCVPixelFormatType_OneComponent8, nil, &buffer), kCVReturnSuccess)
        let maskBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(maskBuffer, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(maskBuffer))
        let stride = CVPixelBufferGetBytesPerRow(maskBuffer)
        memset(base, 0, stride * 2)
        base.assumingMemoryBound(to: UInt8.self)[0] = 255
        CVPixelBufferUnlockBaseAddress(maskBuffer, [])
        let mask = PhotoCaptionRenderer().compactMask(maskBuffer)
        XCTAssertEqual(mask.values, [255, 0, 0, 0, 0, 0, 0, 0])
    }
    @MainActor
    func testDisabledAndNonImageUploadsKeepOriginalBytesWithoutPrompting() async throws {
        let input = CaptionUploadPayload(data: Data([1, 2, 3]), fileName: "a.jpg", mimeType: "image/jpeg")
        for (enabled, isImage) in [(false, true), (true, false)] {
            let result = try await CaptionUploadGate.prepare(input, enabled: enabled, isImage: isImage,
                requestCaption: { _ in XCTFail("Unexpected prompt"); return nil },
                compose: { _, _ in XCTFail("Unexpected rendering"); return input })
            XCTAssertEqual(result, input)
        }
    }

    @MainActor
    func testUploadWaitsForExplicitSubmissionAndReceivesComposedBytes() async throws {
        let input = CaptionUploadPayload(data: Data([1]), fileName: "a.png", mimeType: "image/png")
        let rendered = CaptionUploadPayload(data: Data([2]), fileName: "a-caption.png", mimeType: "image/png")
        let requested = expectation(description: "Prompt is waiting")
        var answer: CheckedContinuation<String?, Never>?
        var events: [String] = []
        let operation = Task { @MainActor in
            let result = try await CaptionUploadGate.prepare(input, enabled: true, isImage: true,
                requestCaption: { _ in
                    await withCheckedContinuation { continuation in
                        answer = continuation
                        events.append("prompt")
                        requested.fulfill()
                    }
                }, compose: { source, text in
                    XCTAssertEqual(source, input)
                    XCTAssertEqual(text, "  用户原文\nHello  ")
                    events.append("compose")
                    return rendered
                })
            if let result {
                events.append("upload")
                XCTAssertEqual(result, rendered)
            }
        }
        await fulfillment(of: [requested], timeout: 3)
        XCTAssertEqual(events, ["prompt"])
        answer?.resume(returning: "  用户原文\nHello  ")
        try await operation.value
        XCTAssertEqual(events, ["prompt", "compose", "upload"])
    }

    @MainActor
    func testCancelSkipsOnlyCurrentQueueEntryAndPromptsAgain() async {
        let queue = SerialUploadQueue()
        var prompts: [String] = []
        var uploads: [String] = []
        for name in ["cancel.png", "submit.png"] {
            queue.enqueue {
                let source = CaptionUploadPayload(data: Data(), fileName: name, mimeType: "image/png")
                guard let result = try await CaptionUploadGate.prepare(source, enabled: true, isImage: true,
                    requestCaption: { _ in prompts.append(name); return name == "cancel.png" ? nil : "Next" },
                    compose: { input, _ in input }) else { return }
                uploads.append(result.fileName!)
            }
        }
        await queue.waitUntilIdle()
        XCTAssertEqual(prompts, ["cancel.png", "submit.png"])
        XCTAssertEqual(uploads, ["submit.png"])
    }

    @MainActor
    func testCompositionFailureNeverReturnsUploadPayload() async {
        let input = CaptionUploadPayload(data: Data(), fileName: nil, mimeType: "image/png")
        for text in ["Text"] {
            do {
                _ = try await CaptionUploadGate.prepare(input, enabled: true, isImage: true,
                    requestCaption: { _ in text }, compose: { _, _ in throw PhotoCaptionError.encodingFailed })
                XCTFail("Must fail before upload")
            } catch {
                XCTAssertTrue(error is PhotoCaptionError)
            }
        }
    }

    @MainActor
    func testBlankCaptionSkipsCompositionAndStillCompresses() async throws {
        let source = CaptionUploadPayload(data: try encode([fixture()], type: .png), fileName: "original.png", mimeType: "image/png")
        for text in ["", " \n\t"] {
            let prepared = try await CaptionUploadGate.prepare(source, enabled: true, isImage: true,
                requestCaption: { _ in text }, compose: { _, _ in XCTFail("Blank must skip composition"); return source })
            XCTAssertEqual(prepared, source)
            var settings = UploadCompressionSettings.default
            settings.isEnabled = true
            settings.mode = .width
            settings.width = 80
            let compressed = try UploadImageCompressor().compress(data: try XCTUnwrap(prepared).data,
                fileName: prepared?.fileName, settings: settings, onProgress: { _ in })
            XCTAssertEqual(compressed.pixelSize.width, 80)
            XCTAssertEqual(compressed.pixelSize.height, 60)
            XCTAssertFalse(compressed.fileName?.contains("-caption") ?? true)
        }
    }

    @MainActor
    func testCaptionSettingDefaultsOffAndRoundTrips() throws {
        var settings = AppSettings.default
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        json.removeValue(forKey: "captionBeforeUpload")
        let legacy = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.captionBeforeUpload)
        settings.captionBeforeUpload = true
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(saved.captionBeforeUpload)
        XCTAssertEqual(saved.profiles, settings.profiles)
        XCTAssertEqual(saved.uploadCompression, settings.uploadCompression)
    }

    func testPNGCompositionChangesPixelsPreservesSizeAndSource() throws {
        let image = try fixture()
        let data = try encode([image], type: .png)
        let original = data
        let result = try PhotoCaptionRenderer().compose(
            CaptionUploadPayload(data: data, fileName: "photo.heic", mimeType: "image/heic"), text: "Hello 世界"
        )
        XCTAssertEqual(data, original)
        XCTAssertEqual(result.fileName, "photo-caption.png")
        XCTAssertEqual(result.mimeType, "image/png")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let output = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(output.width, image.width)
        XCTAssertEqual(output.height, image.height)
        XCTAssertNotEqual(try pixels(output), try pixels(image))
    }

    func testJPEGOrientationIsAppliedBeforeLayout() throws {
        let data = try encode([fixture(width: 320, height: 180)], type: .jpeg, orientation: 6)
        let result = try PhotoCaptionRenderer().compose(
            CaptionUploadPayload(data: data, fileName: "portrait.jpg", mimeType: "image/jpeg"), text: "Portrait"
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        let output = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(output.width, 180)
        XCTAssertEqual(output.height, 320)
    }

    func testGIFRetainsFramesTimingAndLoopCount() throws {
        let data = try encode([fixture(), fixture(second: true)], type: .gif)
        let result = try PhotoCaptionRenderer().compose(
            CaptionUploadPayload(data: data, fileName: "moving.gif", mimeType: "image/gif"), text: "Motion"
        )
        XCTAssertEqual(result.mimeType, "image/gif")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        let global = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let gif = try XCTUnwrap(global[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        XCTAssertEqual(gif[kCGImagePropertyGIFLoopCount] as? Int, 3)
        for index in 0..<2 {
            let p = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            let timing = try XCTUnwrap(p[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            XCTAssertEqual(try XCTUnwrap(timing[kCGImagePropertyGIFUnclampedDelayTime] as? Double),
                           index == 0 ? 0.15 : 0.35, accuracy: 0.01)
        }
        let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let last = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 1, nil))
        XCTAssertNotEqual(try pixels(first), try pixels(last))
    }

    func testMultilingualTextIsPreservedAndFitsWithinCanvas() throws {
        for text in ["毛标标 feat. Pic2Link\n图片与文字", "مرحبا بالعالم", "Hello 👋🏼 café नमस्ते"] {
            let document = try PhotoCaptionRenderer().recommendedDocument(image: fixture(), text: text)
            guard case .text(let annotation) = document.elements.first?.content else {
                return XCTFail("Missing text")
            }
            XCTAssertEqual(annotation.text, text)
            XCTAssertGreaterThanOrEqual(annotation.bounds.minX, 0)
            XCTAssertGreaterThanOrEqual(annotation.bounds.minY, 0)
            XCTAssertLessThanOrEqual(annotation.bounds.maxX, 1)
            XCTAssertLessThanOrEqual(annotation.bounds.maxY, 1)
        }
    }

    func testUnrenderableAndExcessiveTextFailWithoutResult() throws {
        let input = CaptionUploadPayload(data: try encode([fixture()], type: .png), fileName: nil, mimeType: "image/png")
        for text in ["  \n", String(repeating: "长文字", count: 2_001)] {
            XCTAssertThrowsError(try PhotoCaptionRenderer().compose(input, text: text))
        }
        XCTAssertThrowsError(try PhotoCaptionRenderer().compose(
            CaptionUploadPayload(data: Data([0, 1]), fileName: "bad.png", mimeType: "image/png"), text: "Text"
        ))
    }

    private func fixture(width: Int = 320, height: Int = 240, second: Bool = false) throws -> CGImage {
        let c = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(CGColor(red: 0.05, green: 0.2, blue: 0.3, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        c.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1))
        c.fillEllipse(in: CGRect(x: second ? 80 : 120, y: 70, width: 80, height: 80))
        return try XCTUnwrap(c.makeImage())
    }

    private func encode(_ images: [CGImage], type: UTType, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil))
        if type == .gif {
            CGImageDestinationSetProperties(destination,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 3]] as CFDictionary)
        }
        for (index, image) in images.enumerated() {
            var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
            if type == .gif {
                properties[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFUnclampedDelayTime: index == 0 ? 0.15 : 0.35]
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let c = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(c.data), count: image.width * image.height * 4)
    }
}
