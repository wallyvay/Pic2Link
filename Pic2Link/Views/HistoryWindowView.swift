import SwiftUI

/// 历史网格的列计算：单元格宽度固定，列数随容器宽度增减，保证单元格不会超出容器
enum HistoryGridLayout {
    static let cellWidth: CGFloat = 104
    static let spacing: CGFloat = 12

    static func columnCount(fitting width: CGFloat) -> Int {
        let usable = max(width, cellWidth)
        return max(1, Int((usable + spacing) / (cellWidth + spacing)))
    }

    static func columns(fitting width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columnCount(fitting: width))
    }
}

/// 「更多文件」入口打开的独立窗口，展示全部上传记录
struct HistoryWindowView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.allImages.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: HistoryGridLayout.columns(fitting: proxy.size.width),
                                  spacing: HistoryGridLayout.spacing) {
                            ForEach(viewModel.allImages) { image in
                                UploadedImageCell(
                                    image: image,
                                    onTap: { viewModel.copyImageURL(image) },
                                    onDelete: { viewModel.deleteImage(id: image.id) },
                                    cellWidth: HistoryGridLayout.cellWidth
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                HStack {
                    Spacer()

                    Button(L10n.tr("history.clear")) {
                        viewModel.clearAllImages()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundColor(.secondary)

            Text(L10n.tr("history.empty"))
                .font(.headline)
                .foregroundColor(.secondary)

            Text(L10n.tr("history.empty.help"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
