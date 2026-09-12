#if DEBUG
import AppKit
import Combine
import SwiftUI

/// Exercises the real prompt, FIFO gate and renderer without reading accounts or sending data.
@MainActor
final class CaptionUITestHarness: ObservableObject {
    static let shared = CaptionUITestHarness()
    @Published var results = "waiting"
    @Published var image: NSImage?
    @Published var clipboard = ""
    private var window: NSWindow?
    private let pasteboard = NSPasteboard.withUniqueName()
    private lazy var prompt = CaptionPromptController(pasteboard: pasteboard)
    private var statusItem: NSStatusItem?
    private let queue = SerialUploadQueue()

    func start() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-AppleInterfaceStyle"), index + 1 < arguments.count {
            NSApp.appearance = NSAppearance(named: arguments[index + 1] == "Dark" ? .darkAqua : .aqua)
        }
        pasteboard.setString("clipboard-sentinel", forType: .string)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Caption Test")
        statusItem = item
        if let button = item.button { prompt.attach(to: button) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Caption Test Result"
        window.contentView = NSHostingView(rootView: CaptionTestResultView(model: self))
        self.window = window
        let context = CGContext(data: nil, width: 960, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.04, green: 0.15, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 960, height: 640))
        context.setFillColor(CGColor(red: 0.95, green: 0.5, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 580, y: 140, width: 280, height: 280))
        let originalImage = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 960, height: 640))
        let bitmap = NSBitmapImageRep(data: originalImage.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let count = ProcessInfo.processInfo.arguments.contains("-captionBatchForUITesting") ? 2 : 1
        var completedDrafts = 0
        for index in 1...count {
            let source = CaptionUploadPayload(data: data, fileName: "Photo-\(index).png", mimeType: "image/png")
            prompt.present(image: originalImage, fileName: source.fileName) { [self] text in
                completedDrafts += 1
                clipboard = pasteboard.string(forType: .string) ?? ""
                if let text {
                    queue.enqueue { [self] in
                        do {
                            let result = try await CaptionUploadGate.prepare(
                                source, enabled: true, isImage: true, requestCaption: { _ in text },
                                compose: { input, text in
                                    try await Task.detached { try PhotoCaptionRenderer().compose(input, text: text) }.value
                                }
                            )
                            let outcome = result?.data == source.data ? "blank" : "submitted"
                            results += ",Photo-\(index):\(outcome)"
                            image = result.flatMap { NSImage(data: $0.data) }
                        } catch { results += ",failed" }
                    }
                } else { results += ",Photo-\(index):cancelled" }
                if completedDrafts == count {
                    Task { [self] in
                        await self.queue.waitUntilIdle()
                        NSApp.activate(ignoringOtherApps: true)
                        window.center()
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }

    }
}

private struct CaptionTestResultView: View {
    @ObservedObject var model: CaptionUITestHarness
    var body: some View {
        VStack {
            Text(model.results)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Result")
                .accessibilityValue(model.results)
                .accessibilityIdentifier("caption.test.result")
            Text(model.clipboard)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Copied text")
                .accessibilityValue(model.clipboard)
                .accessibilityIdentifier("caption.test.clipboard")
            if let image = model.image {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }.padding(20).frame(width: 480, height: 400)
    }
}
#endif
