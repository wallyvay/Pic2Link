import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pic2Link

final class LivePhotoGIFConverterTests: XCTestCase {
    func testTargetSizeUses480pShortSideWithoutUpscaling() {
        XCTAssertEqual(
            LivePhotoGIFConverter.targetSize(for: UploadPixelSize(width: 1_920, height: 1_080)),
            UploadPixelSize(width: 853, height: 480)
        )
        XCTAssertEqual(
            LivePhotoGIFConverter.targetSize(for: UploadPixelSize(width: 1_080, height: 1_920)),
            UploadPixelSize(width: 480, height: 853)
        )
        XCTAssertEqual(
            LivePhotoGIFConverter.targetSize(for: UploadPixelSize(width: 400, height: 300)),
            UploadPixelSize(width: 400, height: 300)
        )
    }

    func testConverterProducesAnimatedGIFInMemoryAndLeavesVideoUntouched() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let videoURL = try await makeVideo(
            in: directory,
            name: "motion.mov",
            size: CGSize(width: 960, height: 540),
            frameCount: 3,
            contentIdentifier: nil
        )
        let originalVideoData = try Data(contentsOf: videoURL)
        let recorder = CompressionProgressRecorder()

        let output = try await LivePhotoGIFConverter().convert(
            pairedVideoURL: videoURL,
            fileName: "motion.gif",
            onProgress: { recorder.append($0) }
        )

        let source = try XCTUnwrap(CGImageSourceCreateWithData(output.data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.gif.identifier)
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 853)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 480)
        XCTAssertEqual(output.fileName, "motion.gif")
        XCTAssertEqual(output.mimeType, "image/gif")
        XCTAssertEqual(try Data(contentsOf: videoURL), originalVideoData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["motion.mov"])
        XCTAssertEqual(recorder.values.first?.fractionCompleted, 0)
        XCTAssertEqual(recorder.values.last?.fractionCompleted, 1)
    }

    func testClipboardResolverRequiresMatchingLivePhotoResourceIdentifiers() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let identifier = UUID().uuidString
        let stillURL = try makeLivePhotoStill(in: directory, identifier: identifier)
        let videoURL = try await makeVideo(
            in: directory,
            name: "paired.mov",
            size: CGSize(width: 80, height: 60),
            frameCount: 1,
            contentIdentifier: identifier
        )
        let pasteboard = NSPasteboard(name: .init("Pic2LinkLivePhotoTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([stillURL as NSURL, videoURL as NSURL]))

        let source = await ClipboardLivePhotoResolver.firstSource(in: pasteboard)
        XCTAssertEqual(
            source,
            ClipboardLivePhotoSource(stillImageURL: stillURL, pairedVideoURL: videoURL)
        )
    }

    func testClipboardResolverDoesNotTreatStaticImageAsALivePhoto() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let staticURL = try makeStaticPNG(in: directory)
        let videoURL = try await makeVideo(
            in: directory,
            name: "ordinary.mov",
            size: CGSize(width: 80, height: 60),
            frameCount: 1,
            contentIdentifier: UUID().uuidString
        )
        let pasteboard = NSPasteboard(name: .init("Pic2LinkStaticClipboardTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([staticURL as NSURL, videoURL as NSURL]))

        let source = await ClipboardLivePhotoResolver.firstSource(in: pasteboard)
        XCTAssertNil(source)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pic2Link-LivePhotoGIF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeLivePhotoStill(in directory: URL, identifier: String) throws -> URL {
        let url = directory.appendingPathComponent("still.jpg")
        let image = try makeImage(width: 80, height: 60, red: 0.35)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func makeStaticPNG(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("still.png")
        let image = try makeImage(width: 80, height: 60, red: 0.35)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func makeVideo(
        in directory: URL,
        name: String,
        size: CGSize,
        frameCount: Int,
        contentIdentifier: String?
    ) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        if let contentIdentifier {
            let metadata = AVMutableMetadataItem()
            metadata.keySpace = .quickTimeMetadata
            metadata.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
            metadata.value = contentIdentifier as NSString
            metadata.dataType = kCMMetadataBaseDataType_UTF8 as String
            writer.metadata = [metadata]
        }

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height)
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for index in 0..<frameCount {
            let buffer = try makePixelBuffer(size: size, red: UInt8(40 + index * 70))
            XCTAssertTrue(input.isReadyForMoreMediaData)
            XCTAssertTrue(
                adaptor.append(
                    buffer,
                    withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10)
                )
            )
        }
        input.markAsFinished()

        let expectation = expectation(description: "finish writing \(name)")
        writer.finishWriting { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 10)
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "Unknown writer error")
        return url
    }

    private func makePixelBuffer(size: CGSize, red: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ] as CFDictionary,
            &buffer
        )
        XCTAssertEqual(result, kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for row in 0..<Int(size.height) {
            let rowAddress = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<Int(size.width) {
                let pixel = rowAddress.advanced(by: column * 4)
                pixel[0] = 40
                pixel[1] = 90
                pixel[2] = red
                pixel[3] = 255
            }
        }
        return pixelBuffer
    }

    private func makeImage(width: Int, height: Int, red: CGFloat) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: red, green: 0.25, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
