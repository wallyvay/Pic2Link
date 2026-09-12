import AppKit
import Photos
import PhotosUI

/// Presents the system Photos picker as an independent macOS panel. Using the
/// shared library configuration is what allows the result to carry its PhotoKit
/// asset identifier, which is required to obtain the paired Live Photo video.
@MainActor
final class LivePhotoLibraryPicker: NSObject, PHPickerViewControllerDelegate, NSWindowDelegate {
    typealias SelectionHandler = (Result<String, LivePhotoLibraryPickerError>) -> Void

    private var selectionHandler: SelectionHandler?
    private var pickerPanel: NSPanel?
    private var hasFinished = false

    func present(onSelection: @escaping SelectionHandler) {
        hasFinished = false
        selectionHandler = onSelection

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .livePhotos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.tr("picker.livePhoto.title")
        panel.contentViewController = picker
        // Installing PHPicker adopts its initially small view size. Apply the
        // content dimensions afterwards, before centering or showing the panel.
        panel.contentMinSize = NSSize(width: 640, height: 460)
        panel.setContentSize(NSSize(width: 900, height: 650))
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pickerPanel = panel
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let result = results.first else {
            finish(.failure(.cancelled))
            return
        }
        guard let assetIdentifier = result.assetIdentifier, !assetIdentifier.isEmpty else {
            finish(.failure(.assetIdentifierUnavailable))
            return
        }
        finish(.success(assetIdentifier))
    }

    func windowWillClose(_ notification: Notification) {
        finish(.failure(.cancelled))
    }

    private func finish(_ result: Result<String, LivePhotoLibraryPickerError>) {
        guard !hasFinished else { return }
        hasFinished = true

        let handler = selectionHandler
        selectionHandler = nil
        let panel = pickerPanel
        pickerPanel = nil
        panel?.delegate = nil
        panel?.close()
        handler?(result)
    }
}

enum LivePhotoLibraryPickerError: Error, LocalizedError, Equatable {
    case cancelled
    case assetIdentifierUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return L10n.tr("error.photoPickerCancelled")
        case .assetIdentifierUnavailable:
            return L10n.tr("error.photoPickerAssetIdentifier")
        }
    }
}
