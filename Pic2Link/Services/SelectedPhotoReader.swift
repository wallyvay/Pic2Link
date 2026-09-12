import AppKit
import Carbon.HIToolbox

/// Capture this source and its PID before the shortcut changes app focus.
nonisolated enum SelectionApplication: String, Sendable {
    case finder = "com.apple.finder"
    case photos = "com.apple.Photos"

    nonisolated var isAvailable: Bool {
        #if APP_STORE
        return self == .photos
        #else
        return true
        #endif
    }

    nonisolated static func localizedKey(_ key: String) -> String {
        #if APP_STORE
        return key + ".store"
        #else
        return key
        #endif
    }

    nonisolated var selectionProperty: OSType {
        switch self {
        case .finder: return 0x73656c65 // Finder.sdef: sele
        case .photos: return 0x73656c63 // Photos.sdef: selc
        }
    }
    nonisolated var itemProperty: OSType {
        switch self {
        case .finder: return 0x7055524c // pURL
        case .photos: return 0x49442020 // ID  (PhotoKit localIdentifier)
        }
    }
}

nonisolated enum SelectedPhotoSource: Sendable, Equatable, Hashable {
    case file(URL)
    case libraryAsset(String)
}

/// Native, read-only Apple Events. No clipboard, simulated Copy, UI scripting,
/// shell, or Photos-library scanning. Execute on a worker to keep the menu responsive.
enum SelectedPhotoReader {
    nonisolated static func read(
        from application: SelectionApplication,
        processIdentifier: pid_t,
        send: (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor = sendEvent
    ) throws -> [SelectedPhotoSource] {
        // Enforce the distribution boundary before constructing or sending any event,
        // even if a caller bypasses the menu/view-model entry point.
        guard application.isAvailable else { throw SelectedPhotoError.unsupportedApplication }
        let target = NSAppleEventDescriptor(processIdentifier: processIdentifier)
        let selection = try value(of: application.selectionProperty, container: .null(), target: target, send: send)
        let items: [NSAppleEventDescriptor]
        if selection.descriptorType == typeNull { items = [] }
        else if selection.descriptorType == typeAEList {
            items = (0..<selection.numberOfItems).compactMap { selection.atIndex($0 + 1) }
        } else { items = [selection] }
        guard !items.isEmpty else { throw SelectedPhotoError.emptySelection }

        var seen = Set<SelectedPhotoSource>()
        var sources: [SelectedPhotoSource] = []
        for item in items {
            try Task.checkCancellation()
            let source: SelectedPhotoSource
            // fileURLValue coerces arbitrary strings to file paths. Only accept
            // actual file descriptors here; object references must resolve pURL.
            if application == .finder,
               [DescType(typeFileURL), DescType(typeAlias), DescType(typeFSRef)].contains(item.descriptorType),
               let url = item.fileURLValue {
                source = try fileSource(url)
            } else {
                let property = try value(of: application.itemProperty, container: item, target: target, send: send)
                guard let text = property.stringValue, !text.isEmpty else { throw SelectedPhotoError.unavailable }
                switch application {
                case .finder:
                    guard let url = URL(string: text) else { throw SelectedPhotoError.unavailable }
                    source = try fileSource(url)
                case .photos: source = .libraryAsset(text)
                }
            }
            if seen.insert(source).inserted { sources.append(source) }
        }
        return sources
    }

    nonisolated private static func fileSource(_ url: URL) throws -> SelectedPhotoSource {
        guard url.isFileURL else { throw SelectedPhotoError.unavailable }
        return .file(url.standardizedFileURL)
    }

    nonisolated static func propertySpecifier(_ property: OSType, container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: OSType(cProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: property), forKeyword: AEKeyword(keyAEKeyData))
        guard let specifier = record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw SelectedPhotoError.unavailable
        }
        return specifier
    }

    nonisolated private static func value(
        of property: OSType, container: NSAppleEventDescriptor, target: NSAppleEventDescriptor,
        send: (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor
    ) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kAECoreSuite),
            eventID: AEEventID(kAEGetData), targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(try propertySpecifier(property, container: container), forKeyword: AEKeyword(keyDirectObject))
        let reply: NSAppleEventDescriptor
        do { reply = try send(event) }
        catch {
            throw SelectedPhotoError.appleEvent(code: (error as NSError).code)
        }
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw SelectedPhotoError.appleEvent(code: Int(error.int32Value))
        }
        guard let result = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            throw SelectedPhotoError.unavailable
        }
        return result
    }

    nonisolated private static func sendEvent(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 30)
    }
}

enum SelectedPhotoError: Error, LocalizedError, Equatable {
    case unsupportedApplication
    case emptySelection
    case noPhotos
    case unavailable
    case appleEvent(code: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedApplication: return L10n.tr(SelectionApplication.localizedKey("selection.unsupportedApp"))
        case .emptySelection: return L10n.tr(SelectionApplication.localizedKey("selection.empty"))
        case .noPhotos: return L10n.tr("selection.noPhotos")
        case .unavailable: return L10n.tr("selection.unavailable")
        case .appleEvent(let code):
            return code == -1743 || code == -10004
                ? L10n.tr(SelectionApplication.localizedKey("selection.automationDenied")) : L10n.tr("selection.readFailed", code)
        }
    }
}
