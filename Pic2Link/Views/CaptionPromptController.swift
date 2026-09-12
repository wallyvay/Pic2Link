import AppKit
import Combine
import SwiftUI

enum CaptionPanelGeometry {
    static func frame(anchor: NSRect, visibleFrame: NSRect, size: NSSize, depth: Int) -> NSRect {
        let width = min(size.width, max(1, visibleFrame.width - 16))
        let height = min(size.height, max(1, visibleFrame.height - 16))
        let x = min(visibleFrame.maxX - width - 8,
                    max(visibleFrame.minX + 8, anchor.midX - width / 2 + CGFloat(depth) * 16))
        let top = min(visibleFrame.maxY, anchor.minY - 2) - CGFloat(depth) * 28
        return NSRect(x: x, y: max(visibleFrame.minY + 8, top - height), width: width, height: height)
    }
}

private final class CaptionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CaptionPromptController: NSObject, NSWindowDelegate {
    private struct Entry {
        let id: UUID
        let panel: NSPanel
        let model: CaptionPromptModel
    }
    private weak var anchorView: NSView?
    private var entries: [Entry] = []
    private let drafts: CaptionDraftStore

    init(pasteboard: NSPasteboard = .general) {
        drafts = CaptionDraftStore { text in
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(reposition),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(anchorWindowMoved(_:)),
                                               name: NSWindow.didMoveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
    func attach(to view: NSView) { anchorView = view; reposition() }

    func requestCaption(image: NSImage?, fileName: String?) async -> String? {
        await withCheckedContinuation { continuation in
            present(image: image, fileName: fileName) { continuation.resume(returning: $0) }
        }
    }

    /// Each draft owns a panel and completion. The last opened panel receives keyboard focus.
    func present(image: NSImage?, fileName: String?, completion: @escaping (String?) -> Void) {
        NotificationCenter.default.post(name: .captionInputRequested, object: nil)
        var draftID: UUID!
        draftID = drafts.add { [weak self] text in
            self?.removePanel(id: draftID)
            completion(text)
        }
        let id = draftID!
        let model = CaptionPromptModel()
        let panel = CaptionPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = L10n.tr("caption.title") + (fileName.map { " — " + $0 } ?? "")
        panel.identifier = NSUserInterfaceItemIdentifier("caption.window")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: CaptionPromptView(
            image: image, fileName: fileName, model: model,
            onSubmit: { [weak self] in _ = self?.drafts.submit(id: id, text: model.text) },
            onCancel: { [weak self] in self?.drafts.cancel(id: id) }
        ))
        entries.append(Entry(id: id, panel: panel, model: model))
        reposition()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusEditor(in: panel)
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let panel, panel.isKeyWindow else { return }
            self?.focusEditor(in: panel)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = entries.first(where: { $0.panel === window }) else { return }
        drafts.cancel(id: entry.id)
    }

    private func removePanel(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        let wasKey = entry.panel.isKeyWindow
        entry.panel.delegate = nil
        entry.panel.close()
        reposition()
        if wasKey, let remaining = entries.last {
            remaining.panel.makeKeyAndOrderFront(nil)
            focusEditor(in: remaining.panel)
        }
    }

    private func focusEditor(in panel: NSPanel) {
        func find(in view: NSView) -> NSTextView? {
            if let editor = view as? CaptionTextView { return editor }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        if let content = panel.contentView, let editor = find(in: content) { panel.makeFirstResponder(editor) }
    }

    @objc private func anchorWindowMoved(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === anchorView?.window else { return }
        reposition()
    }

    @objc private func reposition() {
        guard !entries.isEmpty else { return }
        let anchor = anchorView.flatMap { view in
            view.window?.convertToScreen(view.convert(view.bounds, to: nil))
        }
        guard let screen = NSScreen.screens.first(where: { screen in
            anchor.map { screen.frame.intersects($0) } ?? false
        }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let resolvedAnchor = anchor.flatMap { screen.frame.intersects($0) ? $0 : nil }
            ?? NSRect(x: visible.maxX - 32, y: visible.maxY + 2, width: 24, height: 24)
        for (index, entry) in entries.enumerated() {
            let depth = entries.count - index - 1
            let frame = CaptionPanelGeometry.frame(anchor: resolvedAnchor, visibleFrame: visible,
                                                   size: NSSize(width: 440, height: 440), depth: depth)
            entry.model.arrowX = min(frame.width - 18, max(18, resolvedAnchor.midX - frame.minX))
            entry.model.isTop = depth == 0
            entry.panel.setFrame(frame, display: true)
        }
    }
}

private final class CaptionPromptModel: ObservableObject {
    @Published var text = ""
    @Published var arrowX: CGFloat = 220
    @Published var isTop = true
}

private final class CaptionTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 || event.keyCode == 76 {
            unmarkText()
            onSubmit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private struct CaptionTextInput: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = CaptionTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.setAccessibilityIdentifier("caption.text")
        editor.setAccessibilityLabel(L10n.tr("caption.text"))
        editor.onSubmit = { [weak editor] in
            context.coordinator.parent.text = editor?.string ?? ""
            context.coordinator.parent.onSubmit()
        }
        editor.onCancel = onCancel
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptionTextInput
        init(_ parent: CaptionTextInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}

private struct CaptionPromptView: View {
    let image: NSImage?
    let fileName: String?
    @ObservedObject var model: CaptionPromptModel
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Path { path in
                path.move(to: CGPoint(x: model.arrowX - 8, y: 8))
                path.addLine(to: CGPoint(x: model.arrowX, y: 0))
                path.addLine(to: CGPoint(x: model.arrowX + 8, y: 8))
                path.closeSubpath()
            }
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(height: 8)
            .opacity(model.isTop ? 1 : 0)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("caption.title")).font(.headline)
                    Spacer()
                    Button(action: onCancel) { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("common.cancel"))
                        .accessibilityIdentifier("caption.close")
                }
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 135)
                        .accessibilityLabel(L10n.tr("caption.preview"))
                }
                if let fileName {
                    Text(fileName).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Text(L10n.tr("caption.optional")).font(.subheadline)
                CaptionTextInput(text: $model.text, onSubmit: onSubmit, onCancel: onCancel)
                    .frame(minHeight: 90)
                    .overlay(Rectangle().stroke(Color(nsColor: .separatorColor)))
                HStack {
                    Button(L10n.tr("common.cancel"), action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("caption.cancel")
                    Spacer()
                    Button(action: onSubmit) {
                        Text(L10n.tr(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? "caption.uploadOriginal" : "caption.submit")) + Text("  ⌘↩")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("caption.submit")
                }
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
        .environment(\.locale, localization.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
    }
}

#if DEBUG
@MainActor
enum CaptionScreenshotViewFactory {
    static func make(image: NSImage, text: String) -> AnyView {
        let model = CaptionPromptModel()
        model.text = text
        return AnyView(CaptionPromptView(image: image, fileName: "Landscape.jpg", model: model,
            onSubmit: {}, onCancel: {}).frame(width: 440, height: 430))
    }
}
#endif
