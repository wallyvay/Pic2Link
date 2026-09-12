import AppKit
import XCTest
@testable import Pic2Link

@MainActor
final class LinkClipboardTests: XCTestCase {
    func testLegacySettingsDefaultToPlainLinksAndNewPreferenceRoundTrips() throws {
        var settings = AppSettings.default
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "copyLinksAsMarkdown")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(decoded.copyLinksAsMarkdown)
        settings.copyLinksAsMarkdown = true
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    func testLegacyHistoryWithoutCaptionsStillDecodes() throws {
        let original = UploadedImage(fileName: "old.png", url: "https://example.com/old.png")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "caption")
        let records = try JSONDecoder().decode([UploadedImage].self, from: JSONSerialization.data(withJSONObject: [legacy]))
        XCTAssertEqual(records, [original])
        XCTAssertEqual(ImageLinkFormatter.string(for: records[0], asMarkdown: true), "![](https://example.com/old.png)")
    }

    func testEachCaptionSurvivesHistoryPersistenceAndCanBeCopiedLater() throws {
        let first = UploadedImage(fileName: "one.png", url: "https://example.com/one.png", caption: "第一张")
        let second = UploadedImage(fileName: "two.png", url: "https://example.com/two.png", caption: "Second image")
        let restored = try JSONDecoder().decode([UploadedImage].self, from: JSONEncoder().encode([first, second]))
        XCTAssertEqual(restored, [first, second])
        XCTAssertEqual(ImageLinkFormatter.string(for: restored[0], asMarkdown: true), "![第一张](https://example.com/one.png)")
        XCTAssertEqual(ImageLinkFormatter.string(for: restored[1], asMarkdown: true), "![Second image](https://example.com/two.png)")
        XCTAssertEqual(ImageLinkFormatter.string(for: restored[0], asMarkdown: false), first.url)
    }

    func testBlankCaptionUsesEmptyAltText() {
        for caption in [nil, "", " \n\t"] as [String?] {
            let image = UploadedImage(fileName: "photo.png", url: "https://example.com/photo.png", caption: caption)
            XCTAssertNil(image.caption)
            XCTAssertEqual(ImageLinkFormatter.string(for: image, asMarkdown: true), "![](https://example.com/photo.png)")
        }
    }

    func testMarkdownEscapesCaptionSyntaxWithoutChangingStoredText() {
        let caption = "  [第一张] *星星* \\path\r\n\nSecond & <tag>  "
        let image = UploadedImage(fileName: "photo.png", url: "https://example.com/photo.png", caption: caption)
        XCTAssertEqual(ImageLinkFormatter.string(for: image, asMarkdown: true),
                       #"![  \[第一张\] \*星星\* \\path  Second \& \<tag\>  ](https://example.com/photo.png)"#)
        XCTAssertEqual(image.caption, caption)
    }

    func testMarkdownPreservesSignedURLAndEscapesDestinationSyntax() {
        let url = "https://example.com/a (b).png?token=a%2Fb&expires=123"
        let image = UploadedImage(fileName: "a (b).png", url: url)
        XCTAssertEqual(ImageLinkFormatter.string(for: image, asMarkdown: true),
                       #"![](https://example.com/a%20\(b\).png?token=a%2Fb&expires=123)"#)
        XCTAssertEqual(ImageLinkFormatter.string(for: image, asMarkdown: false), url)
    }

    func testHistoryCopyWritesBeforeSoundAndAutomaticCopyDoesNotDoublePlay() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let image = UploadedImage(fileName: "photo.png", url: "https://example.com/photo.png", caption: "文案")
        var copiedAtSound: [String] = []
        let clipboard = LinkClipboard(pasteboard: pasteboard) {
            copiedAtSound.append(pasteboard.string(forType: .string) ?? "")
        }
        XCTAssertTrue(clipboard.copy(image, asMarkdown: true, playSound: false))
        XCTAssertEqual(pasteboard.string(forType: .string), "![文案](https://example.com/photo.png)")
        XCTAssertTrue(copiedAtSound.isEmpty)
        XCTAssertTrue(clipboard.copy(image, asMarkdown: true, playSound: true))
        XCTAssertTrue(clipboard.copy(image, asMarkdown: false, playSound: true))
        XCTAssertEqual(copiedAtSound, ["![文案](https://example.com/photo.png)", image.url])
        XCTAssertEqual(pasteboard.string(forType: .string), image.url)
    }

    func testLinkFormatTogglesRecopyLatestUploadInTheNewFormat() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var soundCount = 0
        let clipboard = LinkClipboard(pasteboard: pasteboard) { soundCount += 1 }
        let viewModel = MainViewModel(linkClipboard: clipboard)
        viewModel.uploadedImages = [
            UploadedImage(fileName: "new.png", url: "https://example.com/new.png", caption: "最新"),
            UploadedImage(fileName: "old.png", url: "https://example.com/old.png", caption: "较早")
        ]

        viewModel.appSettings.copyLinksAsMarkdown = true
        viewModel.recopyLatestUploadedLink()

        XCTAssertEqual(pasteboard.string(forType: .string), "![最新](https://example.com/new.png)")
        XCTAssertEqual(soundCount, 1)

        viewModel.appSettings.copyLinksAsMarkdown = false
        viewModel.recopyLatestUploadedLink()

        XCTAssertEqual(pasteboard.string(forType: .string), "https://example.com/new.png")
        XCTAssertEqual(soundCount, 2)
    }

    func testRecopyWithoutHistoryLeavesClipboardUntouched() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep", forType: .string)
        let clipboard = LinkClipboard(pasteboard: pasteboard) { XCTFail("空历史不应播放提示音") }
        let viewModel = MainViewModel(linkClipboard: clipboard)

        viewModel.recopyLatestUploadedLink()

        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
    }
}
