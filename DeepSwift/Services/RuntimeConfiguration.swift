//
//  RuntimeConfiguration.swift
//  DeepSwift
//

import Foundation

/// Resolved process and profile locations for the local DSH runtime.
///
/// Every path is explicit. The configuration never falls back to a user's
/// existing DSH home, global profile, or globally installed runtime.
struct RuntimeConfiguration: Sendable {
    static let expectedDSHVersion = "0.2.1-rc.5"

    let nodePath: String
    let dshBinPath: String
    let bridgePath: String
    let dshHome: String
    let allowProviderEnv: Bool

    /// Absolute repository root recorded at compile time for development runs.
    static var developmentRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // DeepSwift source folder
            .deletingLastPathComponent() // repository root
    }

    static func resolve(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> RuntimeConfiguration {
        let fileManager = FileManager.default
        let root = developmentRoot

        let nodePath = try resolveNode(environment: environment, defaults: defaults, fileManager: fileManager)
        let bridgePath = try resolveBridge(environment: environment, root: root, fileManager: fileManager)
        let dshBinPath = try resolveDSH(environment: environment, root: root, fileManager: fileManager)
        let installedVersion = packageVersion(for: dshBinPath)
        if installedVersion != expectedDSHVersion, environment["DEEPSWIFT_ALLOW_UNSUPPORTED_DSH"] != "1" {
            throw RuntimeSetupError.unsupportedDSH(installed: installedVersion ?? "unknown", expected: expectedDSHVersion)
        }

        let userHome = fileManager.homeDirectoryForCurrentUser
        let homePath: String
        if let explicit = environment["DEEPSWIFT_DSH_HOME"], !explicit.isEmpty {
            homePath = explicit
        } else if let saved = defaults.string(forKey: "dshHomeOverride"), !saved.isEmpty {
            homePath = saved
        } else {
            homePath = userHome
                .appendingPathComponent("Library/Application Support/DeepSwift/DSHHome", isDirectory: true)
                .path
        }
        let homeURL = URL(fileURLWithPath: homePath).standardizedFileURL
        try RuntimeIsolation.validate(home: homeURL, userHome: userHome)

        if !fileManager.fileExists(atPath: homeURL.path) {
            try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        return RuntimeConfiguration(
            nodePath: nodePath,
            dshBinPath: dshBinPath,
            bridgePath: bridgePath,
            dshHome: homeURL.path,
            allowProviderEnv: defaults.bool(forKey: "allowProviderEnv")
        )
    }

    private static func resolveNode(environment: [String: String], defaults: UserDefaults, fileManager: FileManager) throws -> String {
        if let explicit = environment["DEEPSWIFT_NODE_BIN"], fileManager.isExecutableFile(atPath: explicit) {
            return explicit
        }
        if let saved = defaults.string(forKey: "nodePathOverride"), fileManager.isExecutableFile(atPath: saved) {
            return saved
        }
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            (("~/.volta/bin/node") as NSString).expandingTildeInPath,
            (("~/.nvm/current/bin/node") as NSString).expandingTildeInPath
        ]
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        throw RuntimeSetupError.missingNode
    }

    private static func resolveBridge(environment: [String: String], root: URL, fileManager: FileManager) throws -> String {
        var candidates: [String] = []
        if let explicit = environment["DEEPSWIFT_BRIDGE_PATH"] { candidates.append(explicit) }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Bridge/main.mjs").path)
            candidates.append(resources.appendingPathComponent("Bridge/src/main.mjs").path)
        }
        candidates.append(root.appendingPathComponent("Bridge/src/main.mjs").path)
        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return candidate
        }
        throw RuntimeSetupError.missingBridge
    }

    private static func resolveDSH(environment: [String: String], root: URL, fileManager: FileManager) throws -> String {
        var candidates: [String] = []
        if let explicit = environment["DEEPSWIFT_DSH_BIN"] { candidates.append(explicit) }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("DSH/node_modules/@deepseek-ai/dsh/lib/bin.js").path)
            candidates.append(resources.appendingPathComponent("DSH/lib/bin.js").path)
        }
        candidates.append(root.appendingPathComponent(".local/runtime/bridge/node_modules/@deepseek-ai/dsh/lib/bin.js").path)
        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return candidate
        }
        throw RuntimeSetupError.missingDSH
    }

    var dshVersion: String? {
        Self.packageVersion(for: dshBinPath)
    }

    private static func packageVersion(for binPath: String) -> String? {
        let manifest = URL(fileURLWithPath: binPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["version"] as? String
    }
}

/// Path policy that keeps development and application state away from the
/// user's existing DSH installation.
enum RuntimeIsolation {
    static func validate(home: URL, userHome: URL) throws {
        let resolved = home.resolvingSymlinksInPath().standardizedFileURL
        let forbidden = [
            userHome.appendingPathComponent(".dsh").standardizedFileURL,
            userHome.appendingPathComponent(".config/dsh").standardizedFileURL,
            userHome.appendingPathComponent("Library/Application Support/dsh").standardizedFileURL
        ]
        for candidate in forbidden {
            let candidateResolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            if resolved == candidateResolved || home.standardizedFileURL == candidate {
                throw RuntimeSetupError.forbiddenHome(resolved.path)
            }
        }
        if resolved.path == "/" || resolved.path.isEmpty {
            throw RuntimeSetupError.forbiddenHome(resolved.path)
        }
    }
}

enum RuntimeSetupError: LocalizedError {
    case missingNode
    case missingBridge
    case missingDSH
    case forbiddenHome(String)
    case unsupportedDSH(installed: String, expected: String)

    var errorDescription: String? {
        switch self {
        case .missingNode:
            return "No Node.js runtime was found. Install Node 24.9 or later, or set a Node path in Settings › Runtime."
        case .missingBridge:
            return "The DeepSwift bridge was not found in the application or development runtime."
        case .missingDSH:
            return "The pinned official DSH runtime was not found. Run Scripts/prepare-dev-runtime.sh or install a packaged build."
        case let .forbiddenHome(path):
            return "Refusing to use \(path) because it is your existing DSH home. Choose an isolated profile directory."
        case let .unsupportedDSH(installed, expected):
            return "DSH \(installed) is installed, but this client is tested with \(expected). Run Scripts/prepare-dev-runtime.sh, or set DEEPSWIFT_ALLOW_UNSUPPORTED_DSH=1 to override after reviewing Docs/protocol-compatibility.md."
        }
    }
}
