import XCTest
@testable import Pic2Link

final class UploadProgressAndErrorTests: XCTestCase {
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
}
