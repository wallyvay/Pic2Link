import AppKit
import Combine
import UniformTypeIdentifiers

enum PasteboardFileResolver {
    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        var candidates: [URL] = []

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) {
            candidates.append(contentsOf: objects.compactMap { ($0 as? NSURL) as URL? })
        }

        for item in pasteboard.pasteboardItems ?? [] {
            guard let value = item.string(forType: .fileURL) else { continue }

            if let fileURL = URL(string: value), fileURL.isFileURL {
                candidates.append(fileURL)
            } else if value.hasPrefix("/") {
                candidates.append(URL(fileURLWithPath: value))
            }
        }

        var seen: Set<URL> = []
        return candidates.compactMap { candidate in
            guard candidate.isFileURL else { return nil }
            let standardizedURL = candidate.standardizedFileURL
            guard seen.insert(standardizedURL).inserted else { return nil }
            return standardizedURL
        }
    }

    static func firstFileURL(in pasteboard: NSPasteboard) -> URL? {
        fileURLs(in: pasteboard).first
    }

    static func firstImageFileURL(in pasteboard: NSPasteboard) -> URL? {
        for fileURL in fileURLs(in: pasteboard) where isImageFile(fileURL) {
            return fileURL
        }
        return nil
    }

    /// 菜单栏拖放只接收文件，不把文件夹误交给上传队列。
    static func regularFileURLs(in pasteboard: NSPasteboard) -> [URL] {
        fileURLs(in: pasteboard).filter { fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory != true
        }
    }

    static func filePromiseReceivers(in pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        )?
        .compactMap { $0 as? NSFilePromiseReceiver } ?? []
    }

    nonisolated static func isImageFile(_ fileURL: URL) -> Bool {
        let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        guard values?.isDirectory != true else { return false }

        let contentType = values?.contentType ?? UTType(filenameExtension: fileURL.pathExtension)
        return contentType?.conforms(to: .image) ?? false
    }
}

/// 剪切板图片监听器
class PasteboardMonitor: ObservableObject {
    @Published var currentImage: NSImage?
    @Published var lastChangeCount: Int = 0

    // 回调：当检测到新图片时调用
    var imageChanged: ((NSImage?) -> Void)?

    private var timer: Timer?
    private let checkInterval: TimeInterval = 0.5

    /// 开始监听剪切板
    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }

        // 确保 Timer 在主 RunLoop 的 common modes 中运行
        RunLoop.current.add(timer!, forMode: .common)
        print("⏰ Timer 已启动，interval: \(checkInterval)s")
    }

    /// 停止监听
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// 检查剪切板变化
    private func checkForChanges() {
        let currentChangeCount = NSPasteboard.general.changeCount

        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            DispatchQueue.main.async {
                self.getImageFromPasteboard()
            }
        }
    }

    /// 从剪切板获取图片
    func getImageFromPasteboard() {
        let pasteboard = NSPasteboard.general

        // 优先保留复制图片文件的原始 URL，避免 GIF、WebP、HEIC 等被重编码为 PNG。
        if let fileURL = PasteboardFileResolver.firstImageFileURL(in: pasteboard),
           let image = NSImage(contentsOf: fileURL) {
            print("📋 原始图片文件 URL 成功: \(fileURL.path)")
            self.currentImage = image
            self.imageChanged?(image)
            return
        }

        // 方法1：尝试直接获取图片
        if let image = NSImage(pasteboard: pasteboard) {
            print("📋 方法1：NSImage(pasteboard) 成功")
            self.currentImage = image
            self.imageChanged?(image)
            return
        }

        // 方法2：尝试获取 TIFF 数据
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            print("📋 方法2：TIFF 数据成功")
            self.currentImage = image
            self.imageChanged?(image)
            return
        }

        // 方法3：尝试获取 PNG 数据
        if let pngData = pasteboard.data(forType: .png),
           let image = NSImage(data: pngData) {
            print("📋 方法3：PNG 数据成功")
            self.currentImage = image
            self.imageChanged?(image)
            return
        }

        // 没有图片
        self.currentImage = nil
        self.imageChanged?(nil)
    }

    /// 手动刷新（用户点击时调用）
    func refresh() {
        getImageFromPasteboard()
    }
}
