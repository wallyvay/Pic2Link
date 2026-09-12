#if DEBUG
import AppKit
import SwiftUI

/// Renders the real app views with isolated fixtures, without reading user data,
/// opening the status menu, screen capture, or issuing an upload.
@MainActor
enum StoreScreenshotRenderer {
    static let sampleImage: NSImage = {
        NSImage(size: NSSize(width: 960, height: 640), flipped: false) { rect in
            NSGradient(starting: NSColor(red: 0.10, green: 0.28, blue: 0.38, alpha: 1),
                ending: NSColor(red: 0.82, green: 0.91, blue: 0.87, alpha: 1))!.draw(in: rect, angle: 90)
            NSColor(red: 1, green: 0.8, blue: 0.42, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 680, y: 390, width: 110, height: 110)).fill()
            for (height, color) in [(CGFloat(330), NSColor(red: 0.25, green: 0.49, blue: 0.51, alpha: 1)),
                                    (CGFloat(210), NSColor(red: 0.08, green: 0.29, blue: 0.34, alpha: 1))] {
                let path = NSBezierPath()
                path.move(to: .zero)
                path.line(to: CGPoint(x: 0, y: height * 0.35))
                path.line(to: CGPoint(x: 280, y: height))
                path.line(to: CGPoint(x: 510, y: height * 0.4))
                path.line(to: CGPoint(x: 770, y: height * 0.9))
                path.line(to: CGPoint(x: 960, y: height * 0.3))
                path.line(to: CGPoint(x: 960, y: 0))
                path.close(); color.setFill(); path.fill()
            }
            return true
        }
    }()

    static func run() async {
        do {
            let environment = ProcessInfo.processInfo.environment
            let destination = URL(fileURLWithPath: environment["PIC2LINK_SCREENSHOT_OUTPUT"]!)
            let copyURL = URL(fileURLWithPath: environment["PIC2LINK_SCREENSHOT_COPY"]!)
            let copy = try JSONSerialization.jsonObject(with: Data(contentsOf: copyURL)) as! [String: String]
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let model = MainViewModel.shared
            let profiles = [ImageHostProfile(name: "Cloudflare R2", provider: .cloudflareR2, bucketName: "my-images",
                                accessKey: "example-access-key", secretKey: "example-secret-key", publicURL: "https://images.example.com",
                                endpoint: "account-id.r2.cloudflarestorage.com", region: "auto"),
                            ImageHostProfile(name: "WebDAV", provider: .webDAV),
                            ImageHostProfile(name: "Amazon S3", provider: .amazonS3)]
            model.appSettings.profiles = profiles
            model.appSettings.activeProfileID = profiles[0].id
            let thumbnail = NSBitmapImageRep(data: sampleImage.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            model.uploadedImages = (1...3).map { UploadedImage(fileName: "Landscape-\($0).jpg", url: "https://images.example.com/landscape-\($0).jpg", thumbnailData: thumbnail) }

            for appearance in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
                for page in 1...3 {
                    let content: AnyView
                    switch page {
                    case 1: content = AnyView(ContentView().environmentObject(model).background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12)))
                    case 2: content = CaptionScreenshotViewFactory.make(image: sampleImage, text: copy["caption"]!)
                    default: content = AnyView(SettingsView(settings: model.appSettings, onSave: { _ in }, onValidate: { _ in false })
                        .background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12)))
                    }
                    let root = StoreScreenshotCanvas(title: copy["title\(page)"]!, subtitle: copy["subtitle\(page)"]!, content: content)
                        .environment(\.locale, LocalizationManager.shared.locale)
                        .environment(\.layoutDirection, LocalizationManager.shared.layoutDirection)
                    let host = NSHostingView(rootView: root)
                    host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
                    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
                    window.contentView = host
                    window.orderBack(nil)
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(200))
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("\(page)-\(appearance).png"))
                    window.contentView = nil
                    window.orderOut(nil)
                }
            }
            print("Rendered 6 real-view screenshots")
            NSApp.terminate(nil)
        } catch {
            FileHandle.standardError.write(Data("Screenshot rendering failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

private struct StoreScreenshotCanvas: View {
    let title: String
    let subtitle: String
    let content: AnyView
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.87, green: 0.95, blue: 0.96), Color(red: 0.72, green: 0.85, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Pic2Link").font(.system(size: 22, weight: .semibold))
                    Text(title).font(.system(size: 38, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.system(size: 20)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color(red: 0.04, green: 0.19, blue: 0.24))
                .frame(width: 340, alignment: .leading)
                content.shadow(color: .black.opacity(0.15), radius: 24, y: 12)
            }.padding(45)
        }.frame(width: 1280, height: 800)
    }
}
#endif
