//
//  DomainModels.swift
//  DeepSwift
//

import Foundation

struct WorkspaceItem: Codable, Identifiable, Hashable, Sendable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionIds: [String]
    let createdAt: String?
    let updatedAt: String?

    var id: String { workspaceId }

    var displayTitle: String {
        title.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : title
    }

    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

struct ProjectionHints: Codable, Hashable, Sendable {
    let kind: String?
    let asOfSeq: Int?
    let values: [String: JSONValue]?
}

struct SessionSummary: Codable, Identifiable, Hashable, Sendable {
    let sessionId: String
    let updatedAt: Double?
    let running: Bool?
    let blank: Bool?
    let cwd: String?
    let agentAvailable: Bool?
    let formatStatus: String?
    let parentSessionId: String?
    let origin: String?
    let projections: ProjectionHints?

    var id: String { sessionId }

    var title: String? {
        guard let title = projections?.values?["title"]?.stringValue, !title.isEmpty else { return nil }
        return title
    }

    var isRunning: Bool { running == true }

    var isSubagent: Bool { origin == "subagent" || parentSessionId != nil }

    var updatedDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var displayTitle: String {
        title ?? (blank == true ? "New Session" : "Session \(sessionId.suffix(6))")
    }
}

struct RuntimeFacts: Codable, Sendable {
    let state: String?
    let home: String?
    let dshVersion: String?
    let nodeVersion: String?
    let hostPid: Int?
    let hostUrl: String?
    let clientId: String?
    let eventStreamReady: Bool?
    let uptimeMs: Double?
    let protocolVersion: Int?
}

struct ModelSelection: Codable, Hashable, Sendable {
    let provider: String
    let model: String
    let reasoningEffort: String?
}

struct ModelCatalog: Codable, Sendable {
    struct Group: Codable, Identifiable, Sendable {
        struct Model: Codable, Identifiable, Sendable {
            struct ReasoningEffort: Codable, Sendable {
                let id: String
                let name: String?
                let description: String?

                var displayName: String { name ?? id }
            }

            struct Reasoning: Codable, Sendable {
                let defaultEffort: String?
                let efforts: [ReasoningEffort]?
            }

            let id: String
            let name: String?
            let reasoning: Reasoning?
            let available: Bool?

            var displayName: String { name ?? id }
        }

        let id: String
        let name: String?
        let models: [Model]
    }

    struct Failure: Codable, Sendable {
        let id: String?
        let name: String?
        let message: String?

        var displayName: String { name ?? id ?? "Provider" }
    }

    let defaultSelection: ModelSelection?
    let groups: [Group]
    let failures: [Failure]?

    enum CodingKeys: String, CodingKey {
        case defaultSelection = "default"
        case groups
        case failures
    }

    var isEmpty: Bool { groups.allSatisfy(\.models.isEmpty) }

    func contains(_ selection: ModelSelection) -> Bool {
        groups.contains { group in
            group.id == selection.provider && group.models.contains { $0.id == selection.model }
        }
    }

    func model(for selection: ModelSelection) -> Group.Model? {
        groups.first { $0.id == selection.provider }?.models.first { $0.id == selection.model }
    }
}

struct PendingApproval: Identifiable, Hashable, Sendable, Codable {
    let eventId: String
    let sessionId: String
    let toolName: String
    let callId: String?
    let reason: String?
    let displayReason: [String: String]?

    var id: String { eventId }

    var localizedReason: String? {
        guard let displayReason else { return reason }
        if let english = displayReason["en"] { return english }
        return displayReason.values.first
    }
}

struct AskQuestionOption: Codable, Hashable, Sendable {
    let label: String
    let description: String?
}

struct AskQuestion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let question: String
    let detail: String?
    let header: String?
    let options: [AskQuestionOption]?
    let multiSelect: Bool?
    let intent: JSONValue?

    var isPlanReview: Bool {
        intent?["kind"]?.stringValue == "plan-review"
    }
}

struct PendingQuestion: Identifiable, Hashable, Sendable, Codable {
    let eventId: String
    let sessionId: String
    let questions: [AskQuestion]

    var id: String { eventId }
}

/// Text and image parts accepted by the official prompt Remote.
enum PromptContentPart: Encodable, Sendable {
    case text(String)
    case image(data: String, mediaType: String, name: String?)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case mediaType
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case let .image(data, mediaType, name):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mediaType, forKey: .mediaType)
            if let name { try container.encode(name, forKey: .name) }
        }
    }
}

struct AccountLinks: Codable, Sendable {
    let usageUrl: String?
    let topUpUrl: String?
}

struct SignInAttemptView: Codable, Sendable {
    let id: String
    let phase: String
    let authorizeUrl: String?
    let expiresAt: Double?
    let errorCode: String?
}

struct AccountView: Codable, Sendable {
    let status: String
    let links: AccountLinks?
    let attempt: SignInAttemptView?

    var isSignedIn: Bool { status == "credential-stored" }
}

struct WorkspaceFileEntry: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let type: String
    let size: Int?

    var id: String { name }
    var isDirectory: Bool { type == "directory" }
    var isFile: Bool { type == "file" }
}

struct WorkspaceDirectoryListing: Codable, Hashable, Sendable {
    let path: String
    let entries: [WorkspaceFileEntry]
    let truncated: Bool
}

struct WorkspaceFileText: Codable, Hashable, Sendable {
    let absolutePath: String
    let version: String?
    let bytes: Int?
    let offset: Int?
    let text: String
    let lines: Int?
    let eof: Bool?
}

struct WorkspaceFileBytes: Codable, Hashable, Sendable {
    let absolutePath: String
    let version: String?
    let bytes: Int?
    let offset: Int?
    let eof: Bool?
    let dataBase64: String

    var data: Data? { Data(base64Encoded: dataBase64) }
}

enum WorkspacePreviewKind: String, Sendable, Equatable {
    case image
    case pdf
    case unsupported
}

struct AgentPresetRow: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let isDefault: Bool
    let name: String?
    let description: String?
    let broken: String?

    var displayName: String { name ?? id }
}

struct AgentPresetRoster: Codable, Hashable, Sendable {
    let presets: [AgentPresetRow]
}

struct PermissionPresetOption: Codable, Identifiable, Hashable, Sendable {
    let value: String
    let name: String
    let description: String?

    var id: String { value }
}

struct PermissionCatalog: Codable, Hashable, Sendable {
    let options: [PermissionPresetOption]
    let defaultOptions: [PermissionPresetOption]?
    let defaultPreset: String?
}

struct WorkspaceChangedFile: Codable, Identifiable, Hashable, Sendable {
    let path: String
    let display: String
    let added: Int
    let deleted: Int
    let binary: Bool?
    let oversized: Bool?

    var id: String { path }
}

struct WorkspaceChangesSummary: Codable, Hashable, Sendable {
    let turn: Int
    let cwd: String?
    let files: [WorkspaceChangedFile]
    let total: Int
    let added: Int
    let deleted: Int
}

struct WorkspaceDiffHunk: Codable, Hashable, Sendable {
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [String]
}

struct WorkspaceFileDiff: Codable, Hashable, Sendable {
    let kind: String
    let path: String
    let display: String
    let before: Bool?
    let after: Bool?
    let hunks: [WorkspaceDiffHunk]?
    let coarse: Bool?
}

struct TerminalShellInfo: Codable, Hashable, Sendable {
    let path: String
    let args: [String]?
    let name: String?
}

struct TerminalSessionInfo: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let shell: TerminalShellInfo?
    let cwd: String?
    let cols: Int?
    let rows: Int?
    let state: String?
    let exitCode: Int?
    let error: String?

    var displayTitle: String { title?.isEmpty == false ? title! : "Terminal" }
    var isRunning: Bool { state == "running" }
}

struct ComposerAttachment: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let mimeType: String
    let data: Data

    init(name: String, mimeType: String, data: Data) {
        self.id = UUID().uuidString
        self.name = name
        self.mimeType = mimeType
        self.data = data
    }

    var byteCount: Int { data.count }
}

struct BackgroundJob: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String?
    let label: String?
    let status: String?
    let progress: String?
    let detail: String?
    let startedAt: Double?
    let finishedAt: Double?

    var displayLabel: String { label ?? kind ?? "Background Job" }
    var isActive: Bool { status == "running" || status == "stopping" }
}

struct SessionSearchHit: Codable, Identifiable, Hashable, Sendable {
    let sessionId: String
    let snippet: String

    var id: String { "\(sessionId)-\(snippet.hashValue)" }
}

struct CommandDescriptor: Codable, Identifiable, Hashable, Sendable {
    struct Input: Codable, Hashable, Sendable {
        let hint: String?
        let attachments: Bool?
    }

    let definitionId: String?
    let name: String
    let description: String
    let input: Input?

    var id: String { name }
    var slashName: String { "/\(name)" }
}
