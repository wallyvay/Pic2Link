import XCTest
@testable import Pic2Link

final class SandboxFileAccessTests: XCTestCase {
    func testFolderPermissionDoesNotGrantSiblingWithTheSamePrefix() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        XCTAssertTrue(SandboxFileAccess.contains(file: URL(fileURLWithPath: "/tmp/photos/sub/图.png"), in: folder))
        XCTAssertFalse(SandboxFileAccess.contains(file: URL(fileURLWithPath: "/tmp/photos-private/image.png"), in: folder))
        XCTAssertFalse(SandboxFileAccess.contains(file: URL(fileURLWithPath: "/tmp/photos/../private/image.png"), in: folder))
        XCTAssertFalse(SandboxFileAccess.contains(file: folder, in: folder))
    }
}
