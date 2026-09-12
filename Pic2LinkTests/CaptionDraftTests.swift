import AppKit
import XCTest
@testable import Pic2Link

@MainActor
final class CaptionDraftTests: XCTestCase {
    func testSecondDraftCanSubmitBeforeFirstAndCopiesBeforeQueuing() async {
        var events: [String] = []
        let queue = SerialUploadQueue()
        let store = CaptionDraftStore { text in events.append("copy:" + text) }
        let first = store.add { text in
            if text == nil { events.append("cancel:first") }
        }
        let second = store.add { text in
            XCTAssertEqual(text, "  第二张\nSecond  ")
            events.append("close:second")
            queue.enqueue { events.append("upload:second") }
        }
        XCTAssertEqual(store.count, 2)
        XCTAssertTrue(store.submit(id: second, text: "  第二张\nSecond  "))
        await queue.waitUntilIdle()
        XCTAssertEqual(events, ["copy:  第二张\nSecond  ", "close:second", "upload:second"])
        XCTAssertEqual(store.count, 1)
        store.cancel(id: first)
        XCTAssertEqual(events.last, "cancel:first")
    }

    func testBlankIsSubmissionAndDoesNotClearClipboard() {
        var clipboard = "existing"
        var submitted: String?
        let store = CaptionDraftStore { clipboard = $0 }
        let id = store.add { submitted = $0 }
        XCTAssertTrue(store.submit(id: id, text: " \n"))
        XCTAssertEqual(submitted, " \n")
        XCTAssertEqual(clipboard, "existing")
        XCTAssertEqual(store.count, 0)
    }

    func testEachDraftCompletesAtMostOnceAndCancelDoesNotCopy() {
        var calls = 0
        let store = CaptionDraftStore { _ in XCTFail("Cancelled draft must not copy") }
        let id = store.add { text in XCTAssertNil(text); calls += 1 }
        store.cancel(id: id)
        store.cancel(id: id)
        XCTAssertFalse(store.submit(id: id, text: "Too late"))
        XCTAssertEqual(calls, 1)
    }

    func testPanelsCascadeBelowIconAndStayOnEachScreen() {
        for screen in [NSRect(x: 0, y: 0, width: 1440, height: 875),
                       NSRect(x: -1920, y: 200, width: 1920, height: 1055)] {
            for x in [screen.minX + 12, screen.midX, screen.maxX - 12] {
                let anchor = NSRect(x: x, y: screen.maxY + 2, width: 24, height: 24)
                let top = CaptionPanelGeometry.frame(anchor: anchor, visibleFrame: screen,
                    size: NSSize(width: 440, height: 440), depth: 0)
                let behind = CaptionPanelGeometry.frame(anchor: anchor, visibleFrame: screen,
                    size: NSSize(width: 440, height: 440), depth: 1)
                XCTAssertTrue(screen.contains(top))
                XCTAssertTrue(screen.contains(behind))
                XCTAssertLessThanOrEqual(top.maxY, anchor.minY)
                XCTAssertLessThan(behind.maxY, top.maxY)
            }
        }
    }
}
