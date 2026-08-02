import AppKit
import Combine

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

        // 方法4：尝试获取文件 URL
        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let fileURLString = item.string(forType: .fileURL) {
                    if let url = URL(string: fileURLString),
                       url.isFileURL,
                       let image = NSImage(contentsOf: url) {
                        print("📋 方法4：文件 URL 成功: \(url.path)")
                        self.currentImage = image
                        self.imageChanged?(image)
                        return
                    }
                }
            }
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
