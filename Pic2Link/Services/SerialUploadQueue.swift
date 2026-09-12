import Foundation

/// 在主线程上协调上传任务，确保所有入口共用同一个先进先出队列。
@MainActor
final class SerialUploadQueue {
    typealias Operation = @MainActor () async throws -> Void

    private struct Entry {
        let operation: Operation
    }

    private var entries: [Entry] = []
    private var processingTask: Task<Void, Never>?
    private var isExecutingEntry = false
    private var idleContinuations: [CheckedContinuation<Void, Never>] = []

    private let onPendingCountChanged: (Int) -> Void
    private let onBecameActive: () -> Void
    private let onBecameIdle: () -> Void
    private let onOperationError: (Error) -> Void

    init(
        onPendingCountChanged: @escaping (Int) -> Void = { _ in },
        onBecameActive: @escaping () -> Void = {},
        onBecameIdle: @escaping () -> Void = {},
        onOperationError: @escaping (Error) -> Void = { _ in }
    ) {
        self.onPendingCountChanged = onPendingCountChanged
        self.onBecameActive = onBecameActive
        self.onBecameIdle = onBecameIdle
        self.onOperationError = onOperationError
    }

    var pendingCount: Int {
        entries.count
    }

    var isActive: Bool {
        processingTask != nil
    }

    /// 返回新任务前面已有的任务数量，包含正在执行的任务。
    @discardableResult
    func enqueue(_ operation: @escaping Operation) -> Int {
        let tasksAhead = entries.count + (isExecutingEntry ? 1 : 0)
        entries.append(Entry(operation: operation))
        onPendingCountChanged(entries.count)

        if processingTask == nil {
            processingTask = Task { @MainActor [weak self] in
                await self?.processEntries()
            }
        }

        return tasksAhead
    }

    func waitUntilIdle() async {
        guard processingTask != nil else { return }

        await withCheckedContinuation { continuation in
            idleContinuations.append(continuation)
        }
    }

    private func processEntries() async {
        onBecameActive()

        while !entries.isEmpty {
            let entry = entries.removeFirst()
            isExecutingEntry = true
            onPendingCountChanged(entries.count)

            do {
                try await entry.operation()
            } catch {
                onOperationError(error)
            }

            isExecutingEntry = false
        }

        processingTask = nil
        onBecameIdle()

        let continuations = idleContinuations
        idleContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}
