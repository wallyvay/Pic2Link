import XCTest
@testable import Pic2Link

final class SerialUploadQueueTests: XCTestCase {
    private enum TestFailure: Error {
        case expected
    }

    private enum UploadKind: Equatable {
        case image(String)
        case file(String)
    }

    @MainActor
    func testQueueRunsThreeUploadsInFIFOOrder() async {
        var completed: [Int] = []
        let queue = SerialUploadQueue()

        for value in 1...3 {
            queue.enqueue {
                completed.append(value)
            }
        }

        await queue.waitUntilIdle()
        XCTAssertEqual(completed, [1, 2, 3])
    }

    @MainActor
    func testQueueSharesFIFOOrderBetweenImagesAndFiles() async {
        var completed: [UploadKind] = []
        let expected: [UploadKind] = [
            .image("clipboard"),
            .file("animation.gif"),
            .image("screenshot")
        ]
        let queue = SerialUploadQueue()

        for upload in expected {
            queue.enqueue {
                completed.append(upload)
            }
        }

        await queue.waitUntilIdle()
        XCTAssertEqual(completed, expected)
    }

    @MainActor
    func testQueueContinuesAfterAnUploadFails() async {
        var completed: [Int] = []
        var errors: [Error] = []
        let queue = SerialUploadQueue(onOperationError: { errors.append($0) })

        queue.enqueue {
            throw TestFailure.expected
        }
        queue.enqueue {
            completed.append(2)
        }
        queue.enqueue {
            completed.append(3)
        }

        await queue.waitUntilIdle()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(completed, [2, 3])
    }

    @MainActor
    func testQueueExecutesOnlyOneUploadAtATimeAndReportsPendingCount() async {
        var activeUploads = 0
        var maximumActiveUploads = 0
        var pendingCounts: [Int] = []
        let gate = AsyncGate()
        var firstUploadStarted = false
        let queue = SerialUploadQueue(
            onPendingCountChanged: { pendingCounts.append($0) }
        )

        queue.enqueue {
            activeUploads += 1
            maximumActiveUploads = max(maximumActiveUploads, activeUploads)
            firstUploadStarted = true
            await gate.wait()
            activeUploads -= 1
        }
        queue.enqueue {
            activeUploads += 1
            maximumActiveUploads = max(maximumActiveUploads, activeUploads)
            activeUploads -= 1
        }
        queue.enqueue {
            activeUploads += 1
            maximumActiveUploads = max(maximumActiveUploads, activeUploads)
            activeUploads -= 1
        }

        while !firstUploadStarted {
            await Task.yield()
        }

        XCTAssertEqual(queue.pendingCount, 2)
        await gate.open()
        await queue.waitUntilIdle()

        XCTAssertEqual(maximumActiveUploads, 1)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(pendingCounts, [1, 2, 3, 2, 1, 0])
    }

    @MainActor
    func testQueuedUploadCapturesProfileAtEnqueueTime() async {
        struct Profile {
            let name: String
        }

        var activeProfile = Profile(name: "First Host")
        var usedProfiles: [String] = []
        let queue = SerialUploadQueue()

        let firstSnapshot = activeProfile
        queue.enqueue {
            usedProfiles.append(firstSnapshot.name)
        }

        activeProfile = Profile(name: "Second Host")
        let secondSnapshot = activeProfile
        queue.enqueue {
            usedProfiles.append(secondSnapshot.name)
        }

        await queue.waitUntilIdle()
        XCTAssertEqual(usedProfiles, ["First Host", "Second Host"])
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waitingContinuations = continuations
        continuations.removeAll()
        waitingContinuations.forEach { $0.resume() }
    }
}
