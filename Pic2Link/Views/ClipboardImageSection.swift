import SwiftUI
import AppKit

/// 剪切板图片上传区域
struct ClipboardImageSection: View {
    let image: NSImage?
    let isUploading: Bool
    let uploadProgress: UploadProgress
    let shortcutLabel: String
    let onUpload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("clipboard.title"))
                .font(.headline)
                .foregroundColor(.primary)

            if let image = image {
                Button(action: onUpload) {
                    ZStack {
                        // 图片预览
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )

                        // 上传进度覆盖层
                        if isUploading {
                            VStack(spacing: 4) {
                                ProgressView(value: uploadProgress.fractionCompleted, total: 1.0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 200)

                                Text("\(uploadProgress.percentage)%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(.white)

                                if !uploadProgress.byteCountDescription.isEmpty {
                                    Text(uploadProgress.byteCountDescription)
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundColor(.white.opacity(0.78))
                                }
                            }
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(L10n.tr("clipboard.progress"))
                            .accessibilityValue("\(uploadProgress.percentage)%")
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploading)

                // 提示文字
                if !isUploading {
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
}
