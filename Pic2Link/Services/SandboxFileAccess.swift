import AppKit

/// Keeps a user-granted sandbox extension alive while a queued file is read.
final class ScopedFileReadAccess {
    private var scopedURL: URL?

    init(url: URL) {
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
    }

    func finish() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    deinit { scopedURL?.stopAccessingSecurityScopedResource() }
}

@MainActor
enum SandboxFileAccess {
    /// Finder can tell a sandboxed app a path without granting access to it.
    /// Ask the user for that folder once and persist only its read-only bookmark.
    static func selectedFileAccess(to url: URL) throws -> ScopedFileReadAccess {
        let direct = ScopedFileReadAccess(url: url)
#if APP_STORE
        if FileManager.default.isReadableFile(atPath: url.path) { return direct }
        let defaults = UserDefaults.standard
        let key = "selectedPhotoFolderBookmarks"
        let bookmarks = defaults.array(forKey: key) as? [Data] ?? []
        for bookmark in bookmarks {
            var stale = false
            guard let folder = try? URL(resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale),
                contains(file: url, in: folder) else { continue }
            let access = ScopedFileReadAccess(url: folder)
            if FileManager.default.isReadableFile(atPath: url.path) { return access }
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.message = L10n.tr("selection.folderPermission", url.deletingLastPathComponent().lastPathComponent)
        panel.prompt = L10n.tr("selection.allowFolder")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { throw CancellationError() }
        let access = ScopedFileReadAccess(url: folder)
        guard contains(file: url, in: folder), FileManager.default.isReadableFile(atPath: url.path) else {
            throw SelectedPhotoError.unavailable
        }
        let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmarks + [bookmark], forKey: key)
        return access
#else
        return direct
#endif
    }

    nonisolated static func contains(file: URL, in directory: URL) -> Bool {
        let fileComponents = file.standardizedFileURL.pathComponents
        let directoryComponents = directory.standardizedFileURL.pathComponents
        return fileComponents.count > directoryComponents.count && fileComponents.starts(with: directoryComponents)
    }
}
