//
//  AppModelTests.swift
//  DeepSwiftTests
//

import Foundation
import Testing
@testable import DeepSwift

/// A bridge double that records calls and returns scripted values.
actor MockBridgeService: DSHBridgeService {
    nonisolated let notifications: AsyncStream<BridgeNotification>
    private(set) var requests: [(method: String, params: JSONValue)] = []
    private var response: @Sendable (String, JSONValue) throws -> JSONValue

    init(response: @escaping @Sendable (String, JSONValue) throws -> JSONValue = { _, _ in .object([:]) }) {
        var continuation: AsyncStream<BridgeNotification>.Continuation?
        notifications = AsyncStream { continuation = $0 }
        self.response = response
        continuation?.finish()
    }

    func start(configuration: RuntimeConfiguration) async throws {}
    func stop() async {}

    func request(_ method: String, params: JSONValue, timeout: Duration) async throws -> JSONValue {
        requests.append((method, params))
        return try response(method, params)
    }

    func recordedRequests() -> [(method: String, params: JSONValue)] {
        requests
    }
}

@Suite("Application model")
@MainActor
struct AppModelTests {
    @Test("Successful prompt clears the draft and records the official request")
    func sendPrompt() async throws {
        let bridge = MockBridgeService()
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-1"
        model.draft = "Explain the build"

        await model.sendMessage()

        #expect(model.draft.isEmpty)
        #expect(model.errorMessage == nil)
        let requests = await bridge.recordedRequests()
        let call = try #require(requests.last)
        #expect(call.method == "host.call")
        #expect(call.params["namespace"]?.stringValue == "session")
        #expect(call.params["method"]?.stringValue == "prompt")
        let request = try #require(call.params["args"]?["request"])
        #expect(request["sessionId"]?.stringValue == "session-1")
        #expect(request["mode"]?.stringValue == "queue")
        #expect(request["content"]?[0]?["text"]?.stringValue == "Explain the build")
    }

    @Test("Failed prompt retains the draft and surfaces the error")
    func failedPromptRetainsDraft() async throws {
        let bridge = MockBridgeService(response: { _, _ in
            throw BridgeClientError.bridge(code: "host/denied", message: "Denied", details: nil)
        })
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-1"
        model.draft = "Keep me"

        await model.sendMessage()

        #expect(model.draft == "Keep me")
        #expect(model.errorMessage == "Denied")
        #expect(model.pendingPrompts.isEmpty)
    }

    @Test("Approval response uses the closed outcome vocabulary")
    func approvalResponse() async throws {
        let bridge = MockBridgeService()
        let model = AppModel(bridge: bridge)
        let approval = PendingApproval(
            eventId: "event-1",
            sessionId: "session-1",
            toolName: "bash",
            callId: nil,
            reason: "Run the tests",
            displayReason: nil
        )
        model.pendingApprovals = [approval]

        await model.respondApproval(approval, outcome: "allowed-once")

        #expect(model.pendingApprovals.isEmpty)
        let requests = await bridge.recordedRequests()
        let call = try #require(requests.last)
        #expect(call.method == "approval.respond")
        #expect(call.params["eventId"]?.stringValue == "event-1")
        #expect(call.params["outcome"]?.stringValue == "allowed-once")
    }

    @Test("Selecting a session opens the official follow and job streams")
    func selectSessionStreams() async throws {
        let bridge = MockBridgeService()
        let model = AppModel(bridge: bridge)
        model.selectSession("session-1")
        try? await Task.sleep(for: .milliseconds(150))

        let requests = await bridge.recordedRequests()
        let follow = try #require(requests.first { $0.method == "stream.open" && $0.params["endpoint"]?.stringValue == "session/follow" })
        let request = try #require(follow.params["args"]?["request"])
        #expect(request["address"]?["kind"]?.stringValue == "session")
        #expect(request["address"]?["sessionId"]?.stringValue == "session-1")
        #expect(request["assistantStream"]?.boolValue == true)

        let jobs = try #require(requests.first { $0.method == "stream.open" && $0.params["endpoint"]?.stringValue == "job/list" })
        #expect(jobs.params["args"]?["request"]?["sessionId"]?.stringValue == "session-1")
    }

    @Test("Subagent selection uses a subagent address and never prompts")
    func subagentSelection() async throws {
        let bridge = MockBridgeService()
        let model = AppModel(bridge: bridge)
        let child = SessionSummary(
            sessionId: "child",
            updatedAt: 1,
            running: false,
            blank: false,
            cwd: "/tmp/work",
            agentAvailable: false,
            formatStatus: "current",
            parentSessionId: "parent",
            origin: "subagent",
            projections: nil
        )
        model.sessions = [child]
        model.selectSubagent(child)
        try? await Task.sleep(for: .milliseconds(150))

        let requests = await bridge.recordedRequests()
        let follow = try #require(requests.first { $0.method == "stream.open" && $0.params["endpoint"]?.stringValue == "session/follow" })
        let address = try #require(follow.params["args"]?["request"]?["address"])
        #expect(address["kind"]?.stringValue == "subagent")
        #expect(address["parentSessionId"]?.stringValue == "parent")
        #expect(address["childSessionId"]?.stringValue == "child")
        #expect(!requests.contains { $0.method == "stream.open" && $0.params["endpoint"]?.stringValue == "job/list" })

        model.draft = "This must not be sent to a subagent"
        await model.sendMessage()
        let afterSend = await bridge.recordedRequests()
        #expect(!afterSend.contains { $0.method == "host.call" && $0.params["method"]?.stringValue == "prompt" })
    }

    @Test("Image attachments become official image prompt blocks")
    func imageAttachmentPrompt() async throws {
        let bridge = MockBridgeService()
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-1"
        model.attachments = [
            ComposerAttachment(name: "sample.png", mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        ]
        await model.sendMessage()

        #expect(model.attachments.isEmpty)
        let requests = await bridge.recordedRequests()
        let call = try #require(requests.first { $0.method == "host.call" && $0.params["method"]?.stringValue == "prompt" })
        let content = try #require(call.params["args"]?["request"]?["content"]?.arrayValue)
        #expect(content.count == 1)
        #expect(content[0]["type"]?.stringValue == "image")
        #expect(content[0]["mimeType"]?.stringValue == "image/png")
        #expect(content[0]["data"]?.stringValue == Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())
    }

    @Test("Recognized slash commands execute through the official command API")
    func executesSlashCommand() async throws {
        let bridge = MockBridgeService { _, params in
            if params["method"]?.stringValue == "execute" {
                return .object([
                    "commandId": .string("cmd-1"),
                    "result": .object(["kind": .string("success"), "text": .string("current preset workspace-write")])
                ])
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-1"
        model.draft = "/permission"
        await model.sendMessage()

        #expect(model.draft.isEmpty)
        #expect(model.pendingPrompts.isEmpty)
        let requests = await bridge.recordedRequests()
        #expect(requests.contains { $0.method == "host.call" && $0.params["method"]?.stringValue == "execute" })
        #expect(!requests.contains { $0.method == "host.call" && $0.params["method"]?.stringValue == "prompt" })
    }

    @Test("An unrecognized slash line falls back to a normal prompt")
    func unknownCommandFallsBack() async throws {
        let bridge = MockBridgeService { _, params in
            if params["method"]?.stringValue == "execute" {
                return .null
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-1"
        model.draft = "/not-a-command"
        await model.sendMessage()

        #expect(model.draft.isEmpty)
        let requests = await bridge.recordedRequests()
        #expect(requests.contains { $0.method == "host.call" && $0.params["method"]?.stringValue == "prompt" })
    }

    @Test("Workspace files use the session-scoped Host lookup")
    func workspaceFileRequests() async throws {
        let bridge = MockBridgeService { _, params in
            if params["method"]?.stringValue == "list" {
                return .object(["path": .string(""), "entries": .array([]), "truncated": .bool(false)])
            }
            return .object([
                "absolutePath": .string("/tmp/work/README.md"),
                "text": .string("# Readme"),
                "lines": .number(1),
                "eof": .bool(true)
            ])
        }
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-1"

        await model.loadFiles()
        await model.openFile(WorkspaceFileEntry(name: "README.md", type: "file", size: 8))

        let requests = await bridge.recordedRequests()
        let list = try #require(requests.first { $0.method == "host.call" && $0.params["method"]?.stringValue == "list" })
        #expect(list.params["namespace"]?.stringValue == "workspaceFiles")
        #expect(list.params["args"]?["workspaceFileScopeId"]?.stringValue == "session-1")
        #expect(list.params["args"]?["path"]?.stringValue == ".")

        let read = try #require(requests.first { $0.method == "host.call" && $0.params["method"]?.stringValue == "read" })
        #expect(read.params["args"]?["path"]?.stringValue == "README.md")
        #expect(model.filePreview?.text == "# Readme")
    }

    @Test("Visibility filters archived and subagent sessions")
    func visibility() {
        let model = AppModel(bridge: MockBridgeService())
        let userSession = SessionSummary(
            sessionId: "user",
            updatedAt: 2,
            running: false,
            blank: false,
            cwd: "/tmp/work",
            agentAvailable: true,
            formatStatus: "current",
            parentSessionId: nil,
            origin: nil,
            projections: ProjectionHints(kind: "sequenced", asOfSeq: 1, values: ["title": .string("User session")])
        )
        let child = SessionSummary(
            sessionId: "child",
            updatedAt: 3,
            running: false,
            blank: false,
            cwd: "/tmp/work",
            agentAvailable: true,
            formatStatus: "current",
            parentSessionId: "user",
            origin: "subagent",
            projections: nil
        )
        model.sessions = [userSession, child]
        model.archivedSessionIDs = ["user"]
        #expect(model.visibleSessions.isEmpty)
        model.archivedSessionIDs = []
        #expect(model.visibleSessions.map(\.sessionId) == ["user"])
    }
}
