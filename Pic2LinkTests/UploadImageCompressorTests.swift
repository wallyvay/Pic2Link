import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pic2Link

final class UploadImageCompressorTests: XCTestCase {
    func testAllResizeModesMatchReferenceBehavior() throws {
        let source = UploadPixelSize(width: 4_000, height: 3_000)

        var width = UploadCompressionSettings.default
        width.isEnabled = true
        width.mode = .width
        width.width = 1_000
        XCTAssertEqual(
            try UploadResizeCalculator.targetSize(source: source, settings: width),
            UploadPixelSize(width: 1_000, height: 750)
        )

        var height = width
        height.mode = .height
        height.height = 600
        XCTAssertEqual(
            try UploadResizeCalculator.targetSize(source: source, settings: height),
            UploadPixelSize(width: 800, height: 600)
        )

        var percentage = width
        percentage.mode = .percentage
        percentage.percentage = 25
        XCTAssertEqual(
            try UploadResizeCalculator.targetSize(source: source, settings: percentage),
            UploadPixelSize(width: 1_000, height: 750)
        )

        var free = width
        free.mode = .free
        free.width = 320
        free.height = 640
        XCTAssertEqual(
            try UploadResizeCalculator.targetSize(source: source, settings: free),
            UploadPixelSize(width: 320, height: 640)
        )

        var maximum = width
        maximum.mode = .maximum
        maximum.width = 1_000
        maximum.height = 1_000
        XCTAssertEqual(
            try UploadResizeCalculator.targetSize(source: source, settings: maximum),
            UploadPixelSize(width: 1_000, height: 750)
        )
        XCTAssertEqual(
            try UploadResizeCalculator.targetSize(
                source: UploadPixelSize(width: 400, height: 200),
                settings: maximum
            ),
            UploadPixelSize(width: 400, height: 200)
        )
    }

    func testCompressionResizesInMemoryAndLeavesSourceFileUntouched() throws {
        let sourceData = try makeImageData(type: .png, width: 400, height: 200)
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pic2Link-compression-source-\(UUID().uuidString).png")
        try sourceData.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        var settings = UploadCompressionSettings.default
        settings.isEnabled = true
        settings.mode = .maximum
        settings.width = 100
        settings.height = 100

        let output = try UploadImageCompressor().compress(
            data: sourceData,
            fileName: sourceURL.lastPathComponent,
            settings: settings
        )

        XCTAssertEqual(output.pixelSize, UploadPixelSize(width: 100, height: 50))
        XCTAssertEqual(output.fileName, sourceURL.lastPathComponent)
        XCTAssertEqual(output.mimeType, "image/png")
        XCTAssertEqual(try dimensions(of: output.data), UploadPixelSize(width: 100, height: 50))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testAnimatedGIFKeepsEveryFrame() throws {
        let sourceData = try makeAnimatedGIF(width: 80, height: 40)
        var settings = UploadCompressionSettings.default
        settings.isEnabled = true
        settings.mode = .percentage
        settings.percentage = 50

        let output = try UploadImageCompressor().compress(
            data: sourceData,
            fileName: "motion.gif",
            settings: settings
        )

        let source = try XCTUnwrap(CGImageSourceCreateWithData(output.data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        XCTAssertEqual(output.fileName, "motion.gif")
        XCTAssertEqual(output.mimeType, "image/gif")
        XCTAssertEqual(try dimensions(of: output.data), UploadPixelSize(width: 40, height: 20))
    }

    func testMaximumNoOpReturnsOriginalBytesAndCompletesProgress() throws {
        let sourceData = try makeImageData(type: .jpeg, width: 80, height: 40)
        var settings = UploadCompressionSettings.default
        settings.isEnabled = true
        settings.mode = .maximum
        settings.width = 1_920
        settings.height = 1_080
        let reports = CompressionProgressRecorder()

        let output = try UploadImageCompressor().compress(
            data: sourceData,
            fileName: "sample.jpg",
            settings: settings,
            onProgress: { reports.append($0) }
        )

        XCTAssertEqual(output.data, sourceData)
        XCTAssertEqual(reports.values.first?.fractionCompleted, 0)
        XCTAssertEqual(reports.values.last?.fractionCompleted, 1)
    }

    func testInvalidSettingsAndUnusableInputFailBeforeUpload() throws {
        var settings = UploadCompressionSettings.default
        settings.isEnabled = true
        settings.mode = .width
        settings.width = 0

        let sourceData = try makeImageData(type: .png, width: 20, height: 10)
        XCTAssertThrowsError(
            try UploadImageCompressor().compress(
                data: sourceData,
                fileName: "sample.png",
                settings: settings
            )
        ) { error in
            XCTAssertEqual(error as? ImageCompressionError, .invalidDimension)
        }

        settings.width = 10
        XCTAssertThrowsError(
            try UploadImageCompressor().compress(
                data: Data("not-an-image".utf8),
                fileName: "sample.png",
                settings: settings
            )
        ) { error in
            XCTAssertEqual(error as? ImageCompressionError, .unsupportedImage)
        }
    }

    private func makeImageData(type: UTType, width: Int, height: Int) throws -> Data {
        let image = try makeImage(width: width, height: height, red: 0.75)
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func makeAnimatedGIF(width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil)
        )
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )

        for (index, red) in [0.2, 0.8].enumerated() {
            let image = try makeImage(width: width, height: height, red: red)
            let properties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: 0.1 + Double(index) * 0.05
                ]
            ]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
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
        context.setFillColor(CGColor(red: red, green: 0.35, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func dimensions(of data: Data) throws -> UploadPixelSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return UploadPixelSize(
            width: try XCTUnwrap((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue),
            height: try XCTUnwrap((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue)
        )
    }
}

nonisolated final class CompressionProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ImageCompressionProgress] = []

    var values: [ImageCompressionProgress] {
        lock.withLock { storage }
    }

    func append(_ progress: ImageCompressionProgress) {
        lock.withLock {
            storage.append(progress)
        }
    }
}
