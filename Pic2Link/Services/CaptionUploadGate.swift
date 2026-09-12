import Foundation

struct CaptionUploadPayload: Sendable, Equatable {
    let data: Data
    let fileName: String?
    let mimeType: String
}

/// Shared by every upload entry. A nil result means cancellation, never permission to upload
/// the original. An explicitly submitted blank caption keeps the original bytes.
@MainActor
enum CaptionUploadGate {
    static func prepare(
        _ source: CaptionUploadPayload,
        enabled: Bool,
        isImage: Bool,
        requestCaption: (CaptionUploadPayload) async -> String?,
        compose: (CaptionUploadPayload, String) async throws -> CaptionUploadPayload
    ) async throws -> CaptionUploadPayload? {
        guard enabled, isImage else { return source }
        guard let text = await requestCaption(source) else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return source }
        try Task.checkCancellation()
        return try await compose(source, text)
    }
}
