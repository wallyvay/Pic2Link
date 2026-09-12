import XCTest

final class CaptionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSubmitInLightAppearance() { assertSubmission(appearance: "Light") }
    func testSubmitInDarkAppearance() { assertSubmission(appearance: "Dark") }

    func testStackedDraftsSubmitIndependentlyInConfirmationOrder() {
        let app = launch(appearance: "Light", batch: true)
        defer { app.terminate() }
        let first = panel(in: app, index: 1)
        let second = panel(in: app, index: 2)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(first.frame.intersects(second.frame))
        XCTAssertGreaterThan(first.frame.minY, second.frame.minY)
        // No click: the newest panel must already own keyboard focus.
        app.typeText("Second image")
        XCTAssertEqual(second.textViews["caption.text"].value as? String, "Second image")
        XCTAssertEqual(first.textViews["caption.text"].value as? String, "")
        attach(app.screenshot(), name: "caption-stacked")
        app.typeKey(.return, modifierFlags: .command)
        assertClosed(second)
        XCTAssertTrue(first.exists)
        // Closing the top draft returns focus to the remaining editor.
        app.typeText("First image")
        XCTAssertEqual(first.textViews["caption.text"].value as? String, "First image")
        app.typeKey(.return, modifierFlags: .command)
        assertClosed(first)
        assertResult(app, value: "waiting,Photo-2:submitted,Photo-1:submitted", clipboard: "First image")
    }

    func testBlankCaptionUploadsOriginal() {
        let app = launch(appearance: "Light")
        defer { app.terminate() }
        let window = panel(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.buttons["caption.submit"].isEnabled)
        app.typeKey(.return, modifierFlags: .command)
        assertClosed(window)
        assertResult(app, value: "waiting,Photo-1:blank", clipboard: "clipboard-sentinel")
    }

    func testWhitespaceCaptionUploadsOriginal() {
        let app = launch(appearance: "Dark")
        defer { app.terminate() }
        let window = panel(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        app.typeText("  \n  ")
        window.buttons["caption.submit"].click()
        assertClosed(window)
        assertResult(app, value: "waiting,Photo-1:blank", clipboard: "clipboard-sentinel")
    }

    func testEscapeCancelsOnlyNewestDraft() {
        let app = launch(appearance: "Light", batch: true)
        defer { app.terminate() }
        let second = panel(in: app, index: 2)
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        app.typeText("Do not upload")
        app.typeKey(.escape, modifierFlags: [])
        assertClosed(second)
        let first = panel(in: app)
        XCTAssertTrue(first.exists)
        app.typeKey(.return, modifierFlags: .command)
        assertResult(app, value: "waiting,Photo-2:cancelled,Photo-1:blank", clipboard: "clipboard-sentinel")
    }

    func testCloseCancelsWithoutCopyingOrUploading() {
        let app = launch(appearance: "Dark")
        defer { app.terminate() }
        let window = panel(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        app.typeText("Unsubmitted text")
        window.buttons["caption.close"].click()
        assertClosed(window)
        assertResult(app, value: "waiting,Photo-1:cancelled", clipboard: "clipboard-sentinel")
    }

    private func assertSubmission(appearance: String) {
        let app = launch(appearance: appearance)
        defer { app.terminate() }
        let window = panel(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let text = "Hello Pic2Link\nA new view"
        // Typing directly checks initial focus; Return must remain a newline.
        app.typeText(text)
        XCTAssertEqual(window.textViews["caption.text"].value as? String, text)
        attach(window.screenshot(), name: "caption-prompt-\(appearance)")
        app.typeKey(.return, modifierFlags: .command)
        assertClosed(window)
        assertResult(app, value: "waiting,Photo-1:submitted", clipboard: text)
        attach(app.windows["Caption Test Result"].screenshot(), name: "caption-result-\(appearance)")
    }

    private func panel(in app: XCUIApplication, index: Int = 1) -> XCUIElement {
        app.windows["Add Text — Photo-\(index).png"]
    }

    private func assertClosed(_ window: XCUIElement) {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    private func assertResult(_ app: XCUIApplication, value: String, clipboard: String) {
        let result = app.windows["Caption Test Result"].staticTexts["caption.test.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        XCTAssertEqual(result.value as? String, value)
        XCTAssertEqual(app.staticTexts["caption.test.clipboard"].value as? String, clipboard)
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(appearance: String, batch: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-captionForUITesting", "-AppleInterfaceStyle", appearance]
        if batch { app.launchArguments.append("-captionBatchForUITesting") }
        app.launchEnvironment["PIC2LINK_UI_TEST_LANGUAGE"] = "en"
        app.launch()
        return app
    }
}
