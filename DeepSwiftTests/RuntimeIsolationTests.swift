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

    @Test("A packaged runtime resolves before host fallbacks")
    func packagedRuntime() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DeepSwiftPackaged-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let node = resources.appendingPathComponent("Node/bin/node")
        let bridge = resources.appendingPathComponent("Bridge/src/main.mjs")
        let dsh = resources.appendingPathComponent("DSH/node_modules/@deepseek-ai/dsh/lib/bin.js")
        let dshPackage = resources.appendingPathComponent("DSH/node_modules/@deepseek-ai/dsh/package.json")
        for file in [node, bridge, dsh, dshPackage] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        #expect(fm.createFile(atPath: node.path, contents: Data([0x00])))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        try Data().write(to: bridge)
        try Data().write(to: dsh)
        try Data(#"{"version":"0.2.1-rc.5"}"#.utf8).write(to: dshPackage)
        let home = root.appendingPathComponent("Profile", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "DeepSwiftPackaged-\(UUID().uuidString)")!

        let configuration = try RuntimeConfiguration.resolve(
            defaults: defaults,
            environment: ["DEEPSWIFT_DSH_HOME": home.path],
            bundleResources: resources
        )

        #expect(configuration.nodePath == node.path)
        #expect(configuration.bridgePath == bridge.path)
        #expect(configuration.dshBinPath == dsh.path)
        #expect(configuration.dshVersion == "0.2.1-rc.5")
    }

    @Test("Development root contains the bridge source")
    func developmentRoot() {
        let root = RuntimeConfiguration.developmentRoot
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Bridge/src/main.mjs").path))
    }
}
