import Foundation

/// Unsubmitted drafts never occupy the serial upload queue.
@MainActor
final class CaptionDraftStore {
    private var completions: [UUID: (String?) -> Void] = [:]
    private let copyText: (String) -> Void

    init(copyText: @escaping (String) -> Void) { self.copyText = copyText }
    var count: Int { completions.count }

    func add(completion: @escaping (String?) -> Void) -> UUID {
        let id = UUID()
        completions[id] = completion
        return id
    }

    @discardableResult
    func submit(id: UUID, text: String) -> Bool {
        guard let completion = completions.removeValue(forKey: id) else { return false }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { copyText(text) }
        completion(text)
        return true
    }

    func cancel(id: UUID) { completions.removeValue(forKey: id)?(nil) }
}
