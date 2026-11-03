//
//  ConversationProjectionTests.swift
//  DeepSwiftTests
//

import Foundation
import Testing
@testable import DeepSwift

@Suite("Conversation projection")
struct ConversationProjectionTests {
    @Test("Durable messages and tools fold in order")
    func foldsMessagesAndTools() throws {
        var projection = ConversationProjection()
        projection.apply(event: try event("user/message", seq: 1, data: [
            "id": "u1",
            "content": [["type": "text", "text": "Hello"]],
            "source": ["kind": "user"]
        ]))
        projection.apply(event: try event("assistant/message", seq: 2, data: [
            "turn": 1,
            "step": 1,
            "message": [
                "id": "a1",
                "content": [
                    ["type": "reasoning", "text": "Thinking"],
                    ["type": "text", "text": "Working on it."],
                    ["type": "tool-call", "id": "t1", "name": "read", "arguments": "{\"path\":\"a.txt\"}"]
                ]
            ]
        ]))
        projection.apply(event: try event("tool/result", seq: 3, data: [
            "turn": 1,
            "step": 1,
            "message": [
                "id": "t1-result",
                "toolCallId": "t1",
                "source": ["kind": "tool", "callId": "t1"],
                "content": [["type": "text", "text": "file body"]],
                "isError": false
            ]
        ]))

        #expect(projection.items.count == 3)
        #expect(projection.items[0].isUser)
        if case let .assistant(text, reasoning) = projection.items[1].kind {
            #expect(text == "Working on it.")
            #expect(reasoning == "Thinking")
        } else {
            Issue.record("Expected an assistant item")
        }
        guard case let .tool(card) = projection.items[2].kind else {
            Issue.record("Expected a tool card")
            return
        }
        #expect(card.callId == "t1")
        #expect(card.result == "file body")
        #expect(card.isComplete)
        #expect(!card.isError)
    }

    @Test("Duplicate sequence numbers are ignored")
    func deduplicatesSequences() throws {
        var projection = ConversationProjection()
        let event = try event("user/message", seq: 1, data: [
            "id": "u1",
            "content": [["type": "text", "text": "Hello"]],
            "source": ["kind": "user"]
        ])
        projection.apply(event: event)
        projection.apply(event: event)
        #expect(projection.items.count == 1)
    }

    @Test("Older pages prepend without duplicating live items")
    func mergesOlderPages() throws {
        var projection = ConversationProjection()
        projection.apply(event: try event("user/message", seq: 10, data: [
            "id": "u10",
            "content": [["type": "text", "text": "Recent"]],
            "source": ["kind": "user"]
        ]))
        let records = [
            try eventRecord("user/message", seq: 1, data: [
                "id": "u1",
                "content": [["type": "text", "text": "Oldest"]],
                "source": ["kind": "user"]
            ]),
            try eventRecord("user/message", seq: 10, data: [
                "id": "u10",
                "content": [["type": "text", "text": "Recent"]],
                "source": ["kind": "user"]
            ])
        ]
        projection.mergeOlder(records: records, hasMore: false)
        #expect(projection.items.count == 2)
        #expect(projection.firstSeq == 1)
        #expect(!projection.hasMore)
    }

    @Test("Live assistant deltas accumulate until settlement")
    func foldsAssistantStream() throws {
        var projection = ConversationProjection()
        projection.apply(assistantFrame: .object([
            "type": .string("start"),
            "attemptId": .string("attempt-1"),
            "turn": .number(1),
            "step": .number(1)
        ]))
        projection.apply(assistantFrame: .object([
            "type": .string("chunk"),
            "attemptId": .string("attempt-1"),
            "chunk": .object(["type": .string("text-delta"), "index": .number(0), "text": .string("Hel")])
        ]))
        projection.apply(assistantFrame: .object([
            "type": .string("chunk"),
            "attemptId": .string("attempt-1"),
            "chunk": .object(["type": .string("text-delta"), "index": .number(0), "text": .string("lo")])
        ]))
        #expect(projection.live?.text == "Hello")

        projection.apply(assistantFrame: .object([
            "type": .string("end"),
            "attemptId": .string("attempt-1")
        ]))
        #expect(projection.live == nil)
    }

    @Test("Runtime context messages do not enter the transcript")
    func filtersContextMessages() throws {
        var projection = ConversationProjection()
        projection.apply(event: try event("user/message", seq: 1, data: [
            "id": "context-1",
            "content": [["type": "text", "text": "Current runtime context"]],
            "source": ["kind": "runtime-context"]
        ]))
        projection.apply(event: try event("user/message", seq: 2, data: [
            "id": "human-1",
            "content": [["type": "text", "text": "Human prompt"]],
            "source": ["kind": "user"]
        ]))
        #expect(projection.items.count == 1)
        #expect(projection.items.first?.isUser == true)
    }

    @Test("A failed model attempt surfaces its nested error")
    func surfacesAttemptError() throws {
        var projection = ConversationProjection()
        projection.apply(event: try event("assistant/attempt", seq: 5, data: [
            "turn": 1,
            "step": 1,
            "stream": [[
                "type": "chunk",
                "chunk": [
                    "type": "finish",
                    "reason": [
                        "kind": "error",
                        "failure": [
                            "message": "no API key for provider route",
                            "code": "MISSING_CREDENTIAL"
                        ]
                    ]
                ]
            ]]
        ]))
        projection.apply(event: try event("turn/end", seq: 6, data: [
            "turn": 1,
            "reason": [
                "kind": "error",
                "error": ["message": "no API key for provider route", "code": "MISSING_CREDENTIAL"]
            ]
        ]))
        #expect(projection.items.count == 1)
        if case let .error(text) = projection.items[0].kind {
            #expect(text == "no API key for provider route")
        } else {
            Issue.record("Expected an error item")
        }
    }

    @Test("A reconnect baseline restores compact streaming chunks")
    func restoresStreamBaseline() throws {
        var projection = ConversationProjection()
        projection.apply(snapshot: .object([
            "header": .object(["id": .string("s1")]),
            "cursor": .number(3),
            "hasMore": .bool(false),
            "records": .array([]),
            "assistantStream": .object([
                "activeAttempt": .object([
                    "attemptId": .string("attempt-1"),
                    "turn": .number(1),
                    "step": .number(1),
                    "stream": .array([
                        .object(["type": .string("text-chunks"), "texts": .array([.string("Hel"), .string("lo")])]),
                        .object(["type": .string("tool-call-chunks"), "id": .string("t1"), "name": .string("read")])
                    ])
                ])
            ])
        ]))
        #expect(projection.live?.text == "Hello")
        #expect(projection.live?.toolNames == ["read"])
    }

    @Test("Session model selection is retained for availability checks")
    func tracksModelSelection() throws {
        var projection = ConversationProjection()
        projection.apply(event: try event("model/selection", seq: 4, data: [
            "provider": "acme-gateway",
            "model": "acme-chat",
            "reasoningEffort": "high"
        ]))
        let selection = try #require(projection.modelSelection)
        #expect(selection.provider == "acme-gateway")
        #expect(selection.model == "acme-chat")
        #expect(selection.reasoningEffort == "high")

        let catalog = ModelCatalog(
            defaultSelection: nil,
            groups: [.init(id: "acme-gateway", name: "Acme", models: [
                .init(id: "acme-chat", name: "Acme Chat", reasoning: nil, available: true)
            ])],
            failures: nil
        )
        #expect(catalog.contains(selection))
        #expect(!catalog.contains(ModelSelection(provider: "acme-gateway", model: "removed", reasoningEffort: nil)))
    }

    @Test("Snapshot establishes the page cursor and title")
    func appliesSnapshot() throws {
        var projection = ConversationProjection()
        projection.apply(snapshot: .object([
            "header": .object(["id": .string("s1"), "cwd": .string("/tmp/project")]),
            "cursor": .number(12),
            "hasMore": .bool(true),
            "projections": .object(["values": .object(["title": .string("A title")])]),
            "records": .array([
                try eventRecord("user/message", seq: 11, data: [
                    "id": "u11",
                    "content": [["type": "text", "text": "Hi"]],
                    "source": ["kind": "user"]
                ])
            ])
        ]))
        #expect(projection.header?.id == "s1")
        #expect(projection.title == "A title")
        #expect(projection.hasMore)
        #expect(projection.lastSeq == 12)
        #expect(projection.items.count == 1)
    }

    private func event(_ type: String, seq: Int, data: [String: Any]) throws -> SessionWireEvent {
        guard let value = JSONValue.from(any: [
            "type": type,
            "seq": seq,
            "time": 1_700_000_000_000,
            "data": data
        ]) else {
            throw BridgeClientError.protocolViolation("Could not build test event")
        }
        return try #require(SessionWireEvent(value: value))
    }

    private func eventRecord(_ type: String, seq: Int, data: [String: Any]) throws -> JSONValue {
        guard let value = JSONValue.from(any: [
            "type": "event",
            "event": [
                "type": type,
                "seq": seq,
                "time": 1_700_000_000_000,
                "data": data
            ]
        ]) else {
            throw BridgeClientError.protocolViolation("Could not build test record")
        }
        return value
    }
}
