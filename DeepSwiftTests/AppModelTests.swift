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
