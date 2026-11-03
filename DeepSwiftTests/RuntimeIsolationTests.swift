//
//  RuntimeIsolationTests.swift
//  DeepSwiftTests
//

import Foundation
import Testing
@testable import DeepSwift

@Suite("Runtime isolation")
struct RuntimeIsolationTests {
    @Test("Rejects the user's existing DSH home")
    func rejectsDefaultHome() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(throws: RuntimeSetupError.self) {
            try RuntimeIsolation.validate(home: home.appendingPathComponent(".dsh"), userHome: home)
        }
    }

    @Test("Rejects the application-support default DSH directory")
    func rejectsApplicationSupportDSH() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(throws: RuntimeSetupError.self) {
            try RuntimeIsolation.validate(
                home: home.appendingPathComponent("Library/Application Support/dsh"),
                userHome: home
            )
        }
    }

    @Test("Accepts a dedicated DeepSwift profile")
    func acceptsDedicatedProfile() throws {
        let home = URL(fileURLWithPath: "/Users/example")
        try RuntimeIsolation.validate(
            home: home.appendingPathComponent("Library/Application Support/DeepSwift/DSHHome"),
            userHome: home
        )
    }

    @Test("Development root contains the bridge source")
    func developmentRoot() {
        let root = RuntimeConfiguration.developmentRoot
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Bridge/src/main.mjs").path))
    }
}
