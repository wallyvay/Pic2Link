import Foundation

/// A single view of a file while an external app may still be finishing its write.
///
/// Screenshot utilities frequently expose the destination URL before the last write
/// has completed. Keeping this value separate makes the stability decision
/// deterministic and unit-testable.
struct UploadFileStabilitySnapshot: Equatable, Sendable {
    let byteCount: Int64
    let modificationDate: Date

    static func read(from fileURL: URL) throws -> UploadFileStabilitySnapshot {
        let values = try fileURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        guard values.isDirectory != true else {
            throw UploadServiceError.directoryUploadUnsupported
        }

        return UploadFileStabilitySnapshot(
            byteCount: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast
        )
    }
}

/// Tracks two unchanged observations, rather than assuming that the first URL
/// received from a screenshot tool is immediately readable as a finished file.
struct UploadFileStabilityTracker: Sendable {
    private(set) var stableIntervals = 0
    private var previousSnapshot: UploadFileStabilitySnapshot?

    mutating func record(_ snapshot: UploadFileStabilitySnapshot) -> Bool {
        guard snapshot.byteCount > 0 else {
            previousSnapshot = snapshot
            stableIntervals = 0
            return false
        }

        if snapshot == previousSnapshot {
            stableIntervals += 1
        } else {
            stableIntervals = 0
        }
        previousSnapshot = snapshot
        return stableIntervals >= UploadFileReadinessGate.requiredStableIntervals
    }
}

/// Waits briefly for files created by another process to stop changing before
/// copying them into upload memory. It never edits, moves, or retains the source.
struct UploadFileReadinessGate: Sendable {
    static let requiredStableIntervals = 2
    static let sampleIntervalNanoseconds: UInt64 = 250_000_000
    static let maximumSamples = 40

    func waitUntilReady(fileURL: URL) async throws {
        var tracker = UploadFileStabilityTracker()

        for _ in 0..<Self.maximumSamples {
            try Task.checkCancellation()
            let snapshot = try UploadFileStabilitySnapshot.read(from: fileURL)
            if tracker.record(snapshot) {
                return
            }
            try await Task.sleep(nanoseconds: Self.sampleIntervalNanoseconds)
        }

        throw UploadFileReadinessError.fileStillChanging
    }
}

enum UploadFileReadinessError: Error, LocalizedError, Equatable {
    case fileStillChanging

    var errorDescription: String? {
        switch self {
        case .fileStillChanging:
            return L10n.tr("error.fileStillChanging")
        }
    }
}
