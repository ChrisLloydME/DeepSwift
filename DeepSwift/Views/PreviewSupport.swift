//
//  PreviewSupport.swift
//  DeepSwift
//

#if DEBUG
import Foundation
import SwiftUI

/// A bridge double used only by SwiftUI previews. It never starts a process.
struct PreviewBridgeService: DSHBridgeService {
    let notifications: AsyncStream<BridgeNotification>

    init() {
        notifications = AsyncStream { continuation in
            continuation.finish()
        }
    }

    func start(configuration: RuntimeConfiguration) async throws {}
    func request(_ method: String, params: JSONValue, timeout: Duration) async throws -> JSONValue {
        .object([:])
    }
    func stop() async {}
}

@MainActor
enum PreviewData {
    static func model() -> AppModel {
        let model = AppModel(bridge: PreviewBridgeService())
        model.connectionState = .ready
        model.runtimeFacts = RuntimeFacts(
            state: "ready",
            home: "/Users/example",
            dshVersion: "0.2.1-rc.5",
            nodeVersion: "v24.9.0",
            hostPid: 4242,
            hostUrl: nil,
            clientId: "preview",
            eventStreamReady: true,
            uptimeMs: 12_000,
            protocolVersion: 1
        )

        let workspace = WorkspaceItem(
            workspaceId: "ws-1",
            path: "/Users/example/Projects/NativeApp",
            title: "NativeApp",
            sessionIds: ["s-1", "s-2"],
            createdAt: nil,
            updatedAt: nil
        )
        model.workspaces = [workspace]
        model.selectedWorkspaceID = workspace.workspaceId

        let session = SessionSummary(
            sessionId: "s-1",
            updatedAt: Date().timeIntervalSince1970 * 1000,
            running: false,
            blank: false,
            cwd: workspace.path,
            agentAvailable: true,
            formatStatus: "current",
            parentSessionId: nil,
            origin: nil,
            projections: ProjectionHints(
                kind: "sequenced",
                asOfSeq: 5,
                values: ["title": .string("Polish the conversation view")]
            )
        )
        let runningSession = SessionSummary(
            sessionId: "s-2",
            updatedAt: Date().addingTimeInterval(-3_600).timeIntervalSince1970 * 1000,
            running: true,
            blank: false,
            cwd: workspace.path,
            agentAvailable: true,
            formatStatus: "current",
            parentSessionId: nil,
            origin: nil,
            projections: ProjectionHints(
                kind: "sequenced",
                asOfSeq: 2,
                values: ["title": .string("Investigate streaming recovery")]
            )
        )
        model.sessions = [session, runningSession]
        model.selectedSessionID = session.sessionId
        model.conversationSessionID = session.sessionId
        model.models = ModelCatalog(
            defaultSelection: ModelSelection(provider: "deepseek-official", model: "deepseek-v4-flash", reasoningEffort: nil),
            groups: [
                ModelCatalog.Group(id: "deepseek-official", name: "DeepSeek", models: [
                    ModelCatalog.Group.Model(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash", reasoning: nil, available: true)
                ])
            ],
            failures: nil
        )

        apply(to: &model.conversation)
        return model
    }

    private static func apply(to conversation: inout ConversationProjection) {
        conversation.apply(snapshot: .object([
            "header": .object([
                "version": .number(4),
                "id": .string("s-1"),
                "createdAt": .number(Date().timeIntervalSince1970 * 1000),
                "cwd": .string("/Users/example/Projects/NativeApp"),
                "isSeeded": .bool(false),
                "agentPreset": .string("standard")
            ]),
            "hasMore": .bool(false),
            "cursor": .number(8),
            "projections": .object(["values": .object(["title": .string("Polish the conversation view")])]),
            "records": .array([
                event(type: "user/message", seq: 1, data: .object([
                    "id": .string("u1"),
                    "role": .string("user"),
                    "content": .array([.object(["type": .string("text"), "text": .string("Can you review the streaming conversation view and tighten the layout?")])]),
                    "source": .object(["kind": .string("user")])
                ])),
                event(type: "assistant/message", seq: 2, data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "message": .object([
                        "id": .string("a1"),
                        "role": .string("assistant"),
                        "content": .array([
                            .object(["type": .string("reasoning"), "text": .string("Inspect the view, then verify the composer and tool cards.")]),
                            .object(["type": .string("text"), "text": .string("I reviewed the layout. Here are the key points:\n\n- The conversation stays anchored to the bottom.\n- Long code blocks scroll horizontally.\n- Tool output is collapsed until requested.\n\n```swift\nstruct ChatView: View {\n    @Environment(AppModel.self) private var model\n}\n```\n\n| Area | Status |\n| --- | --- |\n| Streaming | Ready |\n| Composer | Ready |")]),
                            .object(["type": .string("tool-call"), "id": .string("t1"), "name": .string("read"), "arguments": .string("{\"file_path\":\"Sources/ChatView.swift\"}")])
                        ]),
                        "source": .object(["kind": .string("model"), "provider": .string("deepseek-official"), "model": .string("deepseek-v4-flash")])
                    ])
                ])),
                event(type: "tool/call", seq: 3, data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "callId": .string("t1"),
                    "name": .string("read"),
                    "arguments": .string("{\"file_path\":\"Sources/ChatView.swift\"}")
                ])),
                event(type: "tool/result", seq: 4, data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "message": .object([
                        "id": .string("t1-result"),
                        "role": .string("tool"),
                        "toolCallId": .string("t1"),
                        "source": .object(["kind": .string("tool"), "callId": .string("t1")]),
                        "content": .array([.object(["type": .string("text"), "text": .string("1: import SwiftUI\n2: \n3: struct ChatView: View {\n4:     var body: some View { … }\n5: }")])]),
                        "isError": .bool(false)
                    ])
                ]))
            ])
        ]))
    }

    private static func event(type: String, seq: Int, data: JSONValue) -> JSONValue {
        .object([
            "type": .string("event"),
            "event": .object([
                "type": .string(type),
                "seq": .number(Double(seq)),
                "time": .number(Date().timeIntervalSince1970 * 1000),
                "data": data,
                "surfaceOp": .string("append")
            ])
        ])
    }
}

#Preview("Conversation") {
    ContentView()
        .environment(PreviewData.model())
        .frame(width: 1_200, height: 800)
}
#endif
