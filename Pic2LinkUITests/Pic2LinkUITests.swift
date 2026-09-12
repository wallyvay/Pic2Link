import XCTest

final class Pic2LinkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEnglishSettingsInLightAppearance() {
        let app = launch(language: "en", appearance: "Light")
        assertSettings(
            app: app,
            languageTitle: "Language",
            profileTitle: "Image Hosts",
            saveTitle: "Save",
            screenshotName: "settings-en-light"
        )
        assertCompressionControls(app: app)
        assertSelectionHelp(app: app)
    }

    func testEnglishSettingsInDarkAppearance() {
        let app = launch(language: "en", appearance: "Dark")
        assertSettings(
            app: app,
            languageTitle: "Language",
            profileTitle: "Image Hosts",
            saveTitle: "Save",
            screenshotName: "settings-en-dark"
        )
        assertCompressionControls(app: app)
        assertSelectionHelp(app: app)
    }

    func testArabicUsesRightToLeftSettingsLayout() {
        let app = launch(language: "ar", appearance: "Light")
        let window = assertSettings(
            app: app,
            languageTitle: "اللغة",
            profileTitle: "مضيفو الصور",
            saveTitle: "حفظ",
            screenshotName: "settings-ar-rtl"
        )
        let languageTitle = app.staticTexts["settings.language.title"]
        let profileTitle = app.staticTexts["settings.profileList.title"]
        XCTAssertLessThan(languageTitle.frame.midX, profileTitle.frame.midX)
        XCTAssertTrue(window.exists)
    }

    func testLongLocalizedSettingsLabelsRemainVisible() {
        let cases = [
            ("de", "Sprache", "Bildhoster", "Sichern"),
            ("fr", "Langue", "Hébergeurs", "Enregistrer"),
            ("ru", "Язык", "Хостинги", "Сохранить")
        ]

        for (language, languageTitle, profileTitle, saveTitle) in cases {
            let app = launch(language: language, appearance: "Light")
            assertSettings(
                app: app,
                languageTitle: languageTitle,
                profileTitle: profileTitle,
                saveTitle: saveTitle,
                screenshotName: "settings-\(language)-light"
            )
            app.terminate()
        }
    }

    @discardableResult
    private func assertSettings(
        app: XCUIApplication,
        languageTitle: String,
        profileTitle: String,
        saveTitle: String,
        screenshotName: String
    ) -> XCUIElement {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        let languageElement = app.staticTexts["settings.language.title"]
        let profileElement = app.staticTexts["settings.profileList.title"]
        XCTAssertTrue(languageElement.waitForExistence(timeout: 3))
        XCTAssertTrue(profileElement.exists)
        XCTAssertEqual(visibleText(languageElement), languageTitle)
        XCTAssertEqual(visibleText(profileElement), profileTitle)

        let saveButton = app.buttons[saveTitle]
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(saveButton.isHittable)

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = screenshotName
        attachment.lifetime = .keepAlways
        add(attachment)
        return window
    }

    private func assertCompressionControls(app: XCUIApplication) {
        let title = app.staticTexts["settings.compression.title"]
        let toggle = app.descendants(matching: .any).matching(identifier: "settings.compression.toggle").firstMatch
        let livePhotoGIFToggle = app.descendants(matching: .any).matching(identifier: "settings.compression.livePhotoGIF.toggle").firstMatch
        let scrollView = app.scrollViews["settings.editor.scroll"]

        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        for _ in 0..<8 where !toggle.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(toggle.exists)
        XCTAssertTrue(toggle.isHittable)
        toggle.click()

        for _ in 0..<8 where !livePhotoGIFToggle.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(livePhotoGIFToggle.waitForExistence(timeout: 3))
        XCTAssertTrue(livePhotoGIFToggle.isEnabled)
        XCTAssertTrue(livePhotoGIFToggle.isHittable)

        XCTAssertTrue(livePhotoGIFToggle.isEnabled)
    }

    private func assertSelectionHelp(app: XCUIApplication) {
        let help = app.staticTexts["settings.selection.help"]
        let scroll = app.scrollViews["settings.editor.scroll"]
        for _ in 0..<8 where !help.isHittable { scroll.swipeUp() }
        XCTAssertTrue(help.exists)
        #if APP_STORE
        XCTAssertEqual(visibleText(help), "⇧⌘U uploads the current selection in Photos. Drag Finder files to the menu bar icon or use Choose File.")
        #else
        XCTAssertEqual(visibleText(help), "⇧⌘U uploads the selected Finder files or the current selection in Photos.")
        #endif
    }

    private func visibleText(_ element: XCUIElement) -> String {
        // AppKit static text can expose its string as AXValue rather than AXTitle.
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    private func launch(language: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-openSettingsForUITesting",
            "-AppleInterfaceStyle",
            appearance
        ]
        app.launchEnvironment["PIC2LINK_UI_TEST_LANGUAGE"] = language
        app.launch()
        return app
    }
}
