//
//  DeepSwiftUITests.swift
//  DeepSwiftUITests
//

import XCTest

final class DeepSwiftUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesIntoNativeWindow() throws {
        let app = XCUIApplication()
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        app.launchEnvironment["DEEPSWIFT_DSH_HOME"] = repositoryRoot
            .appendingPathComponent(".local/profiles/ui-test", isDirectory: true)
            .path
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "The application window did not appear")
        XCTAssertTrue(
            app.staticTexts["DeepSwift"].firstMatch.waitForExistence(timeout: 10),
            "The native welcome surface did not appear"
        )
        XCTAssertTrue(app.buttons["New Workspace"].exists || app.buttons["Choose Workspace…"].exists)
        app.terminate()
    }
}
