import XCTest

@MainActor
final class DromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testNewTabAndKeyboardAvoidance() throws {
        let app = launch()
        let address = app.buttons["Address or page title"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        attach(app, named: "01-new-tab-portrait")

        let field = app.textFields["Search or enter URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        let keyboard = app.keyboards.element
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        field.typeText("keyboard safety")
        XCTAssertKeyboardDoesNotCover(field, keyboard: keyboard, context: "New-tab search")
        attach(app, named: "02-new-tab-keyboard")
    }

    func testAddressBarKeyboardAndTabGrid() throws {
        let app = launch()
        let address = app.buttons["Address or page title"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        address.tap()

        let field = app.textFields["Search or enter URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("example.com")

        let keyboard = app.keyboards.element
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertKeyboardDoesNotCover(field, keyboard: keyboard, context: "Address bar")
        attach(app, named: "03-address-keyboard")

        app.buttons["Cancel editing"].tap()
        app.buttons["Tabs"].tap()
        XCTAssertTrue(app.staticTexts["Tabs"].waitForExistence(timeout: 5))
        attach(app, named: "04-tab-grid-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        attach(app, named: "05-tab-grid-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    func testReviewSheetAndDevToolsKeyboard() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Page review"].waitForExistence(timeout: 20))
        app.buttons["Page review"].tap()
        XCTAssertTrue(app.navigationBars["Page review"].waitForExistence(timeout: 5))
        attach(app, named: "06-page-review")
        app.buttons["Done"].tap()

        app.buttons["More"].tap()
        let developerTools = app.buttons["Developer Tools"]
        XCTAssertTrue(developerTools.waitForExistence(timeout: 5))
        developerTools.tap()

        let field = app.textFields["Evaluate JavaScript..."]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        let keyboard = app.keyboards.element
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        field.typeText("1 + 1")
        XCTAssertKeyboardDoesNotCover(field, keyboard: keyboard, context: "Developer tools")
        attach(app, named: "07-devtools-keyboard")
    }

    func testAccessibilityTextSize() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(app.buttons["Address or page title"].waitForExistence(timeout: 20))
        attach(app, named: "08-new-tab-accessibility-text")
    }

    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func XCTAssertKeyboardDoesNotCover(
        _ field: XCUIElement,
        keyboard: XCUIElement,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(field.isHittable, "\(context) field is not hittable", file: file, line: line)
        XCTAssertLessThanOrEqual(
            field.frame.maxY,
            keyboard.frame.minY + 1,
            "\(context) field is obscured by the keyboard",
            file: file,
            line: line
        )
    }
}
