import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 已上传图片列表
struct UploadedImagesSection: View {
    let images: [UploadedImage]
    let hasMore: Bool
    let onCopyURL: (UploadedImage) -> Void
    let onDelete: (UUID) -> Void
    let onViewMore: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("history.title"))
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if !images.isEmpty {
                    Button(L10n.tr("history.clear")) {
                        onClearAll()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
            }

            if images.isEmpty {
                // 空状态
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)

                    Text(L10n.tr("history.empty"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(L10n.tr("history.empty.help"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                // 图片网格
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(images) { image in
                        UploadedImageCell(
                            image: image,
                            onTap: { onCopyURL(image) },
                            onDelete: { onDelete(image.id) }
                        )
                    }
                }

                // 更多图片按钮
                if hasMore {
                    Button(action: onViewMore) {
                        HStack {
                            Image(systemName: "ellipsis.circle")
                            Text(L10n.tr("history.more"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 单个已上传图片单元格
struct UploadedImageCell: View {
    let image: UploadedImage
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // 缩略图
                if let thumbnailData = image.thumbnailData,
                   let nsImage = NSImage(data: thumbnailData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 104, height: 88)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    FileThumbnailPlaceholder(fileName: image.fileName)
                        .frame(width: 104, height: 88)
                }

                // 文件名
                Text(image.fileName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.tr("history.copyLink")) {
                onTap()
            }

            Button(L10n.tr("common.delete"), role: .destructive) {
                onDelete()
            }
        }
    }
}

private struct FileThumbnailPlaceholder: View {
    let fileName: String

    private var contentType: UTType? {
        let ext = (fileName as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)
    }

    private var fileExtension: String {
        let ext = (fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }

    private var symbolName: String {
        guard let contentType else {
            return "doc"
        }

        if contentType.conforms(to: .pdf) {
            return "doc.richtext"
        }
        if contentType.conforms(to: .archive) {
            return "doc.zipper"
        }
        if contentType.conforms(to: .audio) {
            return "music.note"
        }
        if contentType.conforms(to: .spreadsheet) || contentType.conforms(to: .commaSeparatedText) {
            return "tablecells"
        }
        if contentType.conforms(to: .movie) || contentType.conforms(to: .audiovisualContent) {
            return "film"
        }
        if contentType.conforms(to: .presentation) {
            return "rectangle.on.rectangle"
        }
        if contentType.conforms(to: .text) || contentType.conforms(to: .plainText) || contentType.conforms(to: .sourceCode) {
            return "doc.text"
        }
        if contentType.conforms(to: .image) {
            return "photo"
        }
        return "doc"
    }

    private var tint: Color {
        guard let contentType else {
            return .secondary
        }

        if contentType.conforms(to: .pdf) {
            return .red
        }
        if contentType.conforms(to: .archive) {
            return .orange
        }
        if contentType.conforms(to: .audio) {
            return .pink
        }
        if contentType.conforms(to: .spreadsheet) || contentType.conforms(to: .commaSeparatedText) {
            return .green
        }
        if contentType.conforms(to: .movie) || contentType.conforms(to: .audiovisualContent) {
            return .purple
        }
        if contentType.conforms(to: .presentation) {
            return .orange
        }
        if contentType.conforms(to: .text) || contentType.conforms(to: .plainText) || contentType.conforms(to: .sourceCode) {
            return .blue
        }
        if contentType.conforms(to: .image) {
            return .teal
        }
        return .secondary
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )

            VStack(spacing: 6) {
                Spacer()

                Image(systemName: symbolName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(tint)

                Text(fileExtension)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer()
            }
            .padding(.vertical, 8)

            Image(systemName: "link.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.white)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
                .padding(6)
        }
    }
}
