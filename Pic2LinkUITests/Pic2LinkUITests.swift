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
        XCTAssertEqual(languageElement.label, languageTitle)
        XCTAssertEqual(profileElement.label, profileTitle)

        let saveButton = app.buttons[saveTitle]
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(saveButton.isHittable)

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = screenshotName
        attachment.lifetime = .keepAlways
        add(attachment)
        return window
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
