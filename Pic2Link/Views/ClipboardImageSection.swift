import SwiftUI
import AppKit

/// 剪切板图片上传区域
struct ClipboardImageSection: View {
    let image: NSImage?
    let activeUploadImage: NSImage?
    let activeUploadFileName: String?
    let isPipelineActive: Bool
    let captionStatus: String?
    let isCompressing: Bool
    let compressionProgress: ImageCompressionProgress
    let didCompressActiveUpload: Bool
    let isUploading: Bool
    let uploadProgress: UploadProgress
    let pendingUploadCount: Int
    let shortcutLabel: String
    let onUpload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("clipboard.title"))
                .font(.headline)
                .foregroundColor(.primary)

            if isPipelineActive || image != nil {
                Button(action: onUpload) {
                    ZStack {
                        uploadPreview

                        if isPipelineActive {
                            VStack(spacing: 6) {
                                if let activeUploadFileName {
                                    Text(activeUploadFileName)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                if let captionStatus {
                                    Text(captionStatus)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                }

                                if didCompressActiveUpload {
                                    stageProgress(
                                        title: L10n.tr("clipboard.compressionProgress"),
                                        percentage: compressionProgress.percentage,
                                        fraction: compressionProgress.fractionCompleted,
                                        detail: nil,
                                        isCurrent: isCompressing
                                    )
                                }

                                if isUploading {
                                    stageProgress(
                                        title: L10n.tr("clipboard.uploadProgress"),
                                        percentage: uploadProgress.percentage,
                                        fraction: uploadProgress.fractionCompleted,
                                        detail: uploadProgress.totalBytes > 0
                                            ? uploadProgress.byteCountDescription
                                            : nil,
                                        isCurrent: true
                                    )
                                }

                                if pendingUploadCount > 0 {
                                    Text(L10n.tr("status.queuePending", pendingUploadCount))
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 18)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                captionStatus ?? (isCompressing
                                    ? L10n.tr("clipboard.compressionProgress")
                                    : L10n.tr("clipboard.uploadProgress"))
                            )
                            .accessibilityValue(
                                captionStatus == nil
                                    ? "\(isCompressing ? compressionProgress.percentage : uploadProgress.percentage)%" : ""
                            )
                        }
                    }
                }
                .buttonStyle(.plain)

                // 提示文字
                if !isPipelineActive {
                    Text(L10n.tr("clipboard.uploadPrompt", shortcutLabel))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // 空状态
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text(L10n.tr("clipboard.empty"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private var uploadPreview: some View {
        if let previewImage = isPipelineActive ? activeUploadImage : image {
            Image(nsImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)

                if let activeUploadFileName {
                    Text(activeUploadFileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
        }
    }

    private func stageProgress(
        title: String,
        percentage: Int,
        fraction: Double,
        detail: String?,
        isCurrent: Bool
    ) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(isCurrent ? 1 : 0.78))
                Spacer()
                Text("\(percentage)%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.white)
            }

            ProgressView(value: fraction, total: 1)
                .progressViewStyle(.linear)
                .tint(.white)

            if let detail {
                Text(detail)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: 220)
    }
}
