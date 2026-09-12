import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import XCTest
@testable import Pic2Link

@MainActor
final class SelectedPhotoReaderTests: XCTestCase {
    func testNewShortcutIsCommandShiftUAndLeavesClipboardShortcutDistinct() {
        XCTAssertEqual(KeyboardShortcut.selectedPhotos.key.keyCode, UInt32(kVK_ANSI_U))
        XCTAssertEqual(KeyboardShortcut.selectedPhotos.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertNotEqual(KeyboardShortcut.selectedPhotos, .default)
    }

    func testOnlyFinderAndPhotosAreSelectionSources() {
        XCTAssertEqual(SelectionApplication(rawValue: "com.apple.finder"), .finder)
        XCTAssertEqual(SelectionApplication(rawValue: "com.apple.Photos"), .photos)
        XCTAssertNil(SelectionApplication(rawValue: "com.apple.Preview"))
        XCTAssertNil(SelectionApplication(rawValue: "Amanoya.Pic2Link"))
        XCTAssertTrue(SelectionApplication.photos.isAvailable)
        #if APP_STORE
        XCTAssertFalse(SelectionApplication.finder.isAvailable)
        #else
        XCTAssertTrue(SelectionApplication.finder.isAvailable)
        #endif
    }

    #if APP_STORE
    func testStoreBuildRejectsFinderWithoutSendingAnyAppleEvents() {
        XCTAssertThrowsError(try SelectedPhotoReader.read(from: .finder, processIdentifier: 123) { _ in
            XCTFail("The store build must never send Finder Apple Events")
            return self.reply(.null())
        }) { XCTAssertEqual($0 as? SelectedPhotoError, .unsupportedApplication) }
    }
    #else
    func testFinderFileURLsKeepUnicodeAndNewlinesAndDeduplicateInOrder() throws {
        let first = URL(fileURLWithPath: "/tmp/一张\n照片.png")
        let second = URL(fileURLWithPath: "/tmp/second.jpeg")
        let list = NSAppleEventDescriptor.list()
        for (index, url) in [first, second, first].enumerated() {
            list.insert(NSAppleEventDescriptor(fileURL: url), at: index + 1)
        }
        var calls = 0
        let result = try SelectedPhotoReader.read(from: .finder, processIdentifier: 123) { event in
            calls += 1
            self.assertGet(event, property: SelectionApplication.finder.selectionProperty)
            let address = event.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr))
            XCTAssertEqual(address?.descriptorType, DescType(typeKernelProcessID))
            XCTAssertEqual(address?.data, withUnsafeBytes(of: pid_t(123)) { Data($0) })
            return self.reply(list)
        }
        XCTAssertEqual(result, [.file(first), .file(second)])
        XCTAssertEqual(calls, 1)
    }

    func testFinderObjectReferenceReadsItsURLNotClipboard() throws {
        let item = try SelectedPhotoReader.propertySpecifier(0x706e616d, container: .null())
        let list = NSAppleEventDescriptor.list()
        list.insert(item, at: 1)
        var calls = 0
        let result = try SelectedPhotoReader.read(from: .finder, processIdentifier: 123) { event in
            calls += 1
            if calls == 1 { return self.reply(list) }
            self.assertGet(event, property: SelectionApplication.finder.itemProperty)
            return self.reply(NSAppleEventDescriptor(string: "file:///tmp/selected%20image.gif"))
        }
        XCTAssertEqual(result, [.file(URL(fileURLWithPath: "/tmp/selected image.gif"))])
        XCTAssertEqual(calls, 2)
    }
    #endif

    func testPhotosUsesSelectionAndStablePhotoKitIdentifiers() throws {
        let reference = try SelectedPhotoReader.propertySpecifier(0x706e616d, container: .null())
        let list = NSAppleEventDescriptor.list()
        list.insert(reference, at: 1)
        var calls = 0
        let id = "ABC-123/L0/001"
        let result = try SelectedPhotoReader.read(from: .photos, processIdentifier: 456) { event in
            calls += 1
            self.assertGet(event, property: calls == 1 ? 0x73656c63 : 0x49442020)
            return self.reply(calls == 1 ? list : NSAppleEventDescriptor(string: id))
        }
        XCTAssertEqual(result, [.libraryAsset(id)])
        XCTAssertEqual(calls, 2)
    }

    func testEmptyAndDeniedSelectionsFailWithoutReturningUploadSources() {
        for empty in [NSAppleEventDescriptor.list(), .null()] {
            XCTAssertThrowsError(try SelectedPhotoReader.read(from: .photos, processIdentifier: 123) { _ in self.reply(empty) }) {
                XCTAssertEqual($0 as? SelectedPhotoError, .emptySelection)
            }
        }
        XCTAssertThrowsError(try SelectedPhotoReader.read(from: .photos, processIdentifier: 123) { _ in
            let response = self.reply(.null())
            response.setParam(NSAppleEventDescriptor(int32: -1743), forKeyword: AEKeyword(keyErrorNumber))
            return response
        }) { XCTAssertEqual($0 as? SelectedPhotoError, .appleEvent(code: -1743)) }
    }

    func testNonFileFinderResultIsRejectedAndTimeoutIsReported() {
        #if !APP_STORE
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "reference"), at: 1)
        var calls = 0
        XCTAssertThrowsError(try SelectedPhotoReader.read(from: .finder, processIdentifier: 123) { _ in
            calls += 1
            return self.reply(calls == 1 ? list : NSAppleEventDescriptor(string: "https://example.com/image.png"))
        }) { XCTAssertEqual($0 as? SelectedPhotoError, .unavailable) }
        #endif
        XCTAssertThrowsError(try SelectedPhotoReader.read(from: .photos, processIdentifier: 123) { _ in
            throw NSError(domain: NSOSStatusErrorDomain, code: -1712)
        }) { XCTAssertEqual($0 as? SelectedPhotoError, .appleEvent(code: -1712)) }
    }

    func testCurrentPhotoDataUsesActualFormatAndRetainsOriginalBytes() {
        let data = Data([1, 2, 3])
        let unedited = PhotoLibraryImageSource.makePayload(data: data, originalName: "photo.gif", type: .gif)
        XCTAssertEqual(unedited, CaptionUploadPayload(data: data, fileName: "photo.gif", mimeType: "image/gif"))
        let edited = PhotoLibraryImageSource.makePayload(data: data, originalName: "photo.HEIC", type: .jpeg)
        XCTAssertEqual(edited.data, data)
        XCTAssertEqual(edited.mimeType, "image/jpeg")
        XCTAssertEqual(UTType(filenameExtension: ((edited.fileName ?? "") as NSString).pathExtension), .jpeg)
        XCTAssertTrue(edited.fileName?.hasPrefix("photo.") ?? false)
    }

    private func reply(_ value: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let reply = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEAnswer), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        reply.setParam(value, forKeyword: AEKeyword(keyDirectObject))
        return reply
    }

    private func assertGet(_ event: NSAppleEventDescriptor, property: OSType) {
        XCTAssertEqual(event.eventClass, AEEventClass(kAECoreSuite))
        XCTAssertEqual(event.eventID, AEEventID(kAEGetData))
        let specifier = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
        XCTAssertEqual(specifier?.descriptorType, DescType(typeObjectSpecifier))
        XCTAssertEqual(specifier?.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, property)
    }
}
