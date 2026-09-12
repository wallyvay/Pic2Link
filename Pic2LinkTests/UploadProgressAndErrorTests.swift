import XCTest
import AppKit
@testable import Pic2Link

final class UploadProgressAndErrorTests: XCTestCase {
    func testStatusItemProgressMovesFromCompressionToUpload() {
        var progress = StatusItemPipelineProgress()

        progress.beginCompression()
        progress.updateCompression(0.42)
        XCTAssertEqual(progress.stage, .compression)
        XCTAssertTrue(progress.usesCompression)
        XCTAssertEqual(progress.compressionFraction, 0.42, accuracy: 0.000_001)
        XCTAssertEqual(progress.uploadFraction, 0)
        XCTAssertEqual(progress.activeFraction, 0.42, accuracy: 0.000_001)

        progress.beginUpload(afterCompression: true)
        progress.updateUpload(0.65)
        XCTAssertEqual(progress.stage, .upload)
        XCTAssertEqual(progress.compressionFraction, 1)
        XCTAssertEqual(progress.uploadFraction, 0.65, accuracy: 0.000_001)
        XCTAssertEqual(progress.activeFraction, 0.65, accuracy: 0.000_001)
    }

    func testStatusItemProgressResetsForAnUncompressedQueuedUpload() {
        var progress = StatusItemPipelineProgress()
        progress.beginCompression()
        progress.updateCompression(1)
        progress.beginUpload(afterCompression: true)
        progress.updateUpload(1)

        progress.beginUpload(afterCompression: false)

        XCTAssertEqual(progress.stage, .upload)
        XCTAssertFalse(progress.usesCompression)
        XCTAssertEqual(progress.compressionFraction, 0)
        XCTAssertEqual(progress.uploadFraction, 0)
        XCTAssertEqual(progress.activeFraction, 0)
    }

    func testStatusItemProgressClampsStageValuesAndResets() {
        var progress = StatusItemPipelineProgress()
        progress.beginCompression()
        progress.updateCompression(2)
        XCTAssertEqual(progress.compressionFraction, 1)

        progress.beginUpload(afterCompression: true)
        progress.updateUpload(-1)
        XCTAssertEqual(progress.uploadFraction, 0)

        progress.reset()
        XCTAssertEqual(progress, StatusItemPipelineProgress())
    }

    func testUploadProgressUsesCompletedAndTotalBytes() {
        let progress = UploadProgress(completedBytes: 512, totalBytes: 2_048)

        XCTAssertEqual(progress.fractionCompleted, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(progress.percentage, 25)
        XCTAssertFalse(progress.byteCountDescription.isEmpty)
    }

    func testUploadProgressClampsInvalidValues() {
        XCTAssertEqual(
            UploadProgress(completedBytes: -1, totalBytes: 100).fractionCompleted,
            0
        )
        XCTAssertEqual(
            UploadProgress(completedBytes: 200, totalBytes: 100).fractionCompleted,
            1
        )
        XCTAssertEqual(
            UploadProgress(completedBytes: 10, totalBytes: 0).fractionCompleted,
            0
        )
    }

    func testUploadFailurePreservesStatusCodeAndServerMessage() {
        let description = UploadServiceError.uploadFailed(
            statusCode: 418,
            message: "teapot-response"
        ).localizedDescription

        XCTAssertTrue(description.contains("418"))
        XCTAssertTrue(description.contains("teapot-response"))
    }

    func testUnsupportedFileErrorPreservesProviderAndSummary() {
        let description = UploadServiceError.unsupportedFileType(
            provider: "Flickr",
            summary: "JPEG and PNG"
        ).localizedDescription

        XCTAssertTrue(description.contains("Flickr"))
        XCTAssertTrue(description.contains("JPEG and PNG"))
    }

    func testSimpleUploadErrorsHaveLocalizedDescriptions() {
        let errors: [UploadServiceError] = [
            .invalidResponse,
            .invalidConfig,
            .directoryUploadUnsupported
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertFalse(error.localizedDescription.hasPrefix("error."))
        }
    }

    func testImageFormatResolverDetectsGIFWithoutAFileName() throws {
        let gifData = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))

        XCTAssertEqual(
            ImageFormatResolver.metadata(for: gifData),
            ImageFormatMetadata(filenameExtension: "gif", mimeType: "image/gif")
        )
    }

    func testCopiedGIFFileKeepsOriginalURLNameAndMimeType() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pic2Link 格式测试 \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let gifURL = directoryURL.appendingPathComponent("动画 图片.gif")
        let gifData = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        try gifData.write(to: gifURL)

        let pasteboard = NSPasteboard(name: .init("Pic2LinkTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([gifURL as NSURL]))

        XCTAssertEqual(PasteboardFileResolver.firstImageFileURL(in: pasteboard), gifURL.standardizedFileURL)

        let uploadableFile = try UploadableFile(fileURL: gifURL)
        XCTAssertEqual(uploadableFile.fileName, "动画 图片.gif")
        XCTAssertEqual(uploadableFile.mimeType, "image/gif")
        XCTAssertTrue(uploadableFile.isImage)
        XCTAssertEqual(try Data(contentsOf: uploadableFile.fileURL), gifData)
    }

    func testPasteboardResolverReturnsEveryDraggedFileInOrder() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pic2Link-MultiDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURLs = ["first.png", "第二张.gif", "third.webp"].map {
            directoryURL.appendingPathComponent($0)
        }
        for fileURL in fileURLs {
            try Data([0x00]).write(to: fileURL)
        }

        let pasteboard = NSPasteboard(name: .init("Pic2LinkMultiDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects(fileURLs.map { $0 as NSURL }))

        XCTAssertEqual(
            PasteboardFileResolver.fileURLs(in: pasteboard),
            fileURLs.map(\.standardizedFileURL)
        )
    }

    func testPasteboardRegularFileResolverRejectsDirectories() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pic2Link-RegularFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("upload.png")
        try Data([0x01]).write(to: fileURL)

        let pasteboard = NSPasteboard(name: .init("Pic2LinkRegularFileTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([directoryURL as NSURL, fileURL as NSURL]))

        XCTAssertEqual(
            PasteboardFileResolver.regularFileURLs(in: pasteboard),
            [fileURL.standardizedFileURL]
        )
    }

    func testFileStabilityTrackerRequiresTwoUnchangedNonEmptyIntervals() {
        var tracker = UploadFileStabilityTracker()
        let initial = UploadFileStabilitySnapshot(
            byteCount: 128,
            modificationDate: Date(timeIntervalSince1970: 100)
        )

        XCTAssertFalse(tracker.record(initial))
        XCTAssertFalse(tracker.record(initial))
        XCTAssertTrue(tracker.record(initial))
        XCTAssertEqual(tracker.stableIntervals, UploadFileReadinessGate.requiredStableIntervals)
    }

    func testFileStabilityTrackerRestartsWhenTheScreenshotChangesOrIsEmpty() {
        var tracker = UploadFileStabilityTracker()
        let first = UploadFileStabilitySnapshot(
            byteCount: 128,
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let stillWriting = UploadFileStabilitySnapshot(
            byteCount: 256,
            modificationDate: Date(timeIntervalSince1970: 101)
        )
        let empty = UploadFileStabilitySnapshot(
            byteCount: 0,
            modificationDate: Date(timeIntervalSince1970: 102)
        )

        XCTAssertFalse(tracker.record(first))
        XCTAssertFalse(tracker.record(first))
        XCTAssertFalse(tracker.record(stillWriting))
        XCTAssertEqual(tracker.stableIntervals, 0)
        XCTAssertFalse(tracker.record(empty))
        XCTAssertEqual(tracker.stableIntervals, 0)
    }

    func testOtherImageFilesKeepTheirOriginalMetadata() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pic2Link-ImageMetadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let cases = [
            ("animated.webp", "image/webp"),
            ("photo.heic", "image/heic"),
            ("vector.svg", "image/svg+xml"),
            ("animated.png", "image/png")
        ]

        for (fileName, expectedMimeType) in cases {
            let fileURL = directoryURL.appendingPathComponent(fileName)
            try Data([0x00]).write(to: fileURL)

            let uploadableFile = try UploadableFile(fileURL: fileURL)
            XCTAssertEqual(uploadableFile.fileName, fileName)
            XCTAssertEqual(uploadableFile.mimeType, expectedMimeType)
            XCTAssertTrue(uploadableFile.isImage)
        }
    }
}
