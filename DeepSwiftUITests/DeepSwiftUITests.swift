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

    @MainActor
    func testInspectorHasOneToggleAndEmptyState() throws {
        let app = XCUIApplication()
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        app.launchEnvironment["DEEPSWIFT_DSH_HOME"] = repositoryRoot
            .appendingPathComponent(".local/profiles/ui-inspector-test", isDirectory: true)
            .path
        app.launch()
        app.activate()

        let toggles = app.buttons.matching(NSPredicate(format: "label == %@", "Inspector"))
        XCTAssertTrue(toggles.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(toggles.count, 1, "Inspector visibility must have one authoritative toolbar control")
        XCTAssertTrue(toggles.firstMatch.isEnabled)

        toggles.firstMatch.click()
        XCTAssertTrue(app.staticTexts["No Session Selected"].waitForExistence(timeout: 5), app.debugDescription)

        toggles.firstMatch.click()
        let disappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["No Session Selected"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 5), .completed)
        app.terminate()
    }
}
