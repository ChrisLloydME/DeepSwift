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
        addTeardownBlock { app.terminate() }
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
        addTeardownBlock { app.terminate() }
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

    @MainActor
    func testModelsSettingsOpensProviderDirectory() throws {
        let app = XCUIApplication()
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let home = repositoryRoot
            .appendingPathComponent(".local/profiles/ui-settings-test", isDirectory: true)
        try? FileManager.default.removeItem(at: home)
        app.launchEnvironment["DEEPSWIFT_DSH_HOME"] = home.path
        addTeardownBlock { app.terminate() }
        app.launch()
        app.activate()

        XCTAssertTrue(app.staticTexts["DeepSwift"].firstMatch.waitForExistence(timeout: 15))
        app.typeKey(",", modifierFlags: .command)

        let modelsTab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Models"))
            .firstMatch
        XCTAssertTrue(modelsTab.waitForExistence(timeout: 10), app.debugDescription)
        modelsTab.click()

        XCTAssertTrue(app.staticTexts["Model Providers"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["DeepSeek API Key"].waitForExistence(timeout: 10), app.debugDescription)

        let addMenu = app.menuButtons.matching(NSPredicate(format: "title == %@", "Add Model Provider")).firstMatch
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5), app.debugDescription)
        addMenu.click()
        let customItem = app.menuItems["Custom Provider…"]
        XCTAssertTrue(customItem.waitForExistence(timeout: 5), app.debugDescription)
        customItem.click()

        XCTAssertTrue(app.staticTexts["Add Model Provider"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.textFields["providerIDField"].exists, app.debugDescription)

        app.textFields["providerIDField"].click()
        app.typeText("acme-ui-test")
        app.textFields["providerDisplayNameField"].click()
        app.typeText("Acme UI Test")
        app.textFields["providerBaseURLField"].click()
        app.typeText("http://127.0.0.1:9/v1")
        app.descendants(matching: .any)["providerAPIKeyField"].firstMatch.click()
        app.typeText("sk-test-not-real")
        app.textFields["modelIDField"].firstMatch.click()
        app.typeText("acme-chat")
        app.buttons["Save"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["Acme UI Test"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["acme-ui-test"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["acme-chat"].waitForExistence(timeout: 10), app.debugDescription)
        let configured = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "API key configured")
        ).firstMatch
        XCTAssertTrue(configured.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }

}
