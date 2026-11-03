//
//  ConversationModels.swift
//  DeepSwift
//

import Foundation

struct SessionHeader: Codable, Hashable, Sendable {
    let version: Int?
    let id: String
    let createdAt: Double?
    let cwd: String?
    let parentSession: String?
    let isSeeded: Bool?
    let origin: String?
    let agentPreset: String?

    var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

struct SessionWireEvent: Hashable, Sendable {
    let type: String
    let seq: Int
    let time: Double
    let data: JSONValue
    let surfaceOp: JSONValue?

    var date: Date { Date(timeIntervalSince1970: time / 1000) }

    init?(value: JSONValue) {
        guard let type = value["type"]?.stringValue,
              let seq = value["seq"]?.intValue,
              let data = value["data"] else { return nil }
        self.type = type
        self.seq = seq
        self.time = value["time"]?.doubleValue ?? 0
        self.data = data
        self.surfaceOp = value["surfaceOp"]
    }
}

struct ToolCard: Identifiable, Hashable, Sendable {
    var callId: String
    var name: String
    var arguments: String
    var result: String?
    var isError: Bool
    var isComplete: Bool

    var id: String { callId }

    var displayName: String {
        let known: [String: String] = [
            "bash": "Shell",
            "read": "Read File",
            "write": "Write File",
            "edit": "Edit File",
            "glob": "Find Files",
            "grep": "Search",
            "todo_write": "Todo List",
            "bash_output": "Shell Output",
            "kill_shell": "Stop Shell",
            "ask_user_question": "Question",
            "exit_plan_mode": "Plan Review",
            "task": "Task",
            "web_search": "Web Search",
            "web_fetch": "Fetch URL"
        ]
        return known[name] ?? (name.isEmpty ? "Tool" : name.replacingOccurrences(of: "_", with: " ").capitalized)
    }

    var symbolName: String {
        switch name {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit": return "pencil.and.scribble"
        case "glob": return "folder.badge.magnifyingglass"
        case "grep": return "magnifyingglass"
        case "todo_write": return "checklist"
        case "web_search": return "globe"
        case "web_fetch": return "link"
        default: return "wrench.and.screwdriver"
        }
    }

    /// One-line context drawn from the tool arguments without assuming one schema.
    var subtitle: String {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments.isEmpty ? "" : String(arguments.prefix(120))
        }
        for key in ["command", "file_path", "path", "pattern", "query", "url", "description", "objective"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value.replacingOccurrences(of: "\n", with: " ")
            }
        }
        if let keys = object.keys.sorted().first, let value = object[keys] as? String {
            return value
        }
        return ""
    }

    var prettyArguments: String {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return arguments
        }
        return text
    }
}

struct ChatItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case user(text: String)
        case assistant(text: String, reasoning: String?)
        case tool(ToolCard)
        case notice(text: String)
        case error(text: String)
    }

    let id: String
    let seq: Int
    let time: Date
    var kind: Kind

    var isUser: Bool {
        if case .user = kind { return true }
        return false
    }

    var isAssistant: Bool {
        if case .assistant = kind { return true }
        return false
    }
}

struct LiveAssistant: Identifiable, Hashable, Sendable {
    var attemptId: String
    var turn: Int?
    var step: Int?
    var text: String = ""
    var reasoning: String = ""
    var toolNames: [String] = []

    var id: String { attemptId }

    var hasVisibleContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !toolNames.isEmpty
    }
}

/// Incrementally folds durable Session events into a renderable conversation.
///
/// Durable sequence numbers are the identity and deduplication key. Message
/// and tool-call ids provide stable identity when a compacted replacement
/// carries the same content at a new sequence.
struct ConversationProjection: Sendable {
    private(set) var items: [ChatItem] = []
    private(set) var header: SessionHeader?
    private(set) var title: String?
    private(set) var live: LiveAssistant?
    private(set) var lastSeq: Int = -1
    private(set) var firstSeq: Int?
    private(set) var hasMore: Bool = false
    private(set) var isLoaded: Bool = false
    private(set) var permissionPreset: String?
    private(set) var modelSelection: ModelSelection?

    private var seenSequences: Set<Int> = []
    private var indexByItemID: [String: Int] = [:]
    private var toolIndexByCallID: [String: Int] = [:]

    var streamingText: String { live?.text ?? "" }
    var streamingReasoning: String { live?.reasoning ?? "" }

    mutating func reset() {
        items = []
        header = nil
        title = nil
        live = nil
        lastSeq = -1
        firstSeq = nil
        hasMore = false
        isLoaded = false
        permissionPreset = nil
        modelSelection = nil
        seenSequences = []
        indexByItemID = [:]
        toolIndexByCallID = [:]
    }

    mutating func apply(snapshot value: JSONValue) {
        reset()
        isLoaded = true
        if let headerValue = value["header"] {
            header = try? headerValue.decode(SessionHeader.self)
        }
        hasMore = value["hasMore"]?.boolValue ?? false
        if let projections = value["projections"]?["values"], let titleValue = projections["title"]?.stringValue {
            title = titleValue
        }
        if let active = value["assistantStream"]?["activeAttempt"] {
            applyStreamingBaseline(active)
        }
        if let records = value["records"]?.arrayValue {
            for record in records { apply(record: record) }
        }
        // The connection snapshot's cursor can be newer than the last surface
        // event in the page; retain it so a later opening can page accurately.
        if let cursor = value["cursor"]?.intValue, cursor > lastSeq {
            lastSeq = cursor
        }
    }

    mutating func mergeOlder(records: [JSONValue], hasMore: Bool) {
        // Reuse the same fold in a scratch projection so older pages follow
        // exactly the same event semantics as live frames.
        var olderProjection = ConversationProjection()
        for record in records {
            guard record["type"]?.stringValue == "event", let eventValue = record["event"],
                  let event = SessionWireEvent(value: eventValue), !seenSequences.contains(event.seq) else { continue }
            olderProjection.apply(event: event)
        }
        let older = olderProjection.items.filter { !seenSequences.contains($0.seq) }.sorted { $0.seq < $1.seq }
        guard !older.isEmpty else {
            self.hasMore = hasMore
            return
        }
        items.insert(contentsOf: older, at: 0)
        for item in older { seenSequences.insert(item.seq) }
        indexByItemID = [:]
        toolIndexByCallID = [:]
        for (index, item) in items.enumerated() {
            indexByItemID[item.id] = index
            if case let .tool(card) = item.kind { toolIndexByCallID[card.callId] = index }
        }
        self.hasMore = hasMore
        if let first = items.first?.seq { firstSeq = first }
    }

    mutating func apply(event: SessionWireEvent) {
        guard !seenSequences.contains(event.seq) else { return }
        seenSequences.insert(event.seq)
        lastSeq = max(lastSeq, event.seq)
        applyContent(event)
    }

    private mutating func apply(record: JSONValue) {
        guard record["type"]?.stringValue == "event",
              let eventValue = record["event"],
              let event = SessionWireEvent(value: eventValue) else { return }
        apply(event: event)
    }

    private mutating func applyContent(_ event: SessionWireEvent) {
        switch event.type {
        case "user/message":
            applyUserMessage(event)
        case "assistant/message":
            applyAssistantMessage(event)
        case "assistant/attempt":
            applyAssistantAttempt(event)
        case "tool/call":
            applyToolCall(event)
        case "tool/result":
            applyToolResult(event)
        case "turn/end":
            applyTurnEnd(event)
        case "session/title":
            if let value = event.data["title"]?.stringValue { title = value }
        case "permission/preset":
            if let value = event.data["preset"]?.stringValue { permissionPreset = value }
        case "model/selection":
            modelSelection = try? event.data.decode(ModelSelection.self)
        case "command/done":
            let text = event.data["text"]?.stringValue
            let kind = event.data["kind"]?.stringValue
            if let text, !text.isEmpty {
                appendNotice(
                    id: "command-\(event.seq)",
                    seq: event.seq,
                    time: event.date,
                    kind: kind == "error" ? .error(text: text) : .notice(text: text)
                )
            }
        case "error", "turn/error":
            let message = event.data["message"]?.stringValue ?? "The agent reported an error."
            appendNotice(id: "error-\(event.seq)", seq: event.seq, time: event.date, kind: .error(text: message))
        default:
            // Preserve a readable fallback for a new surface event instead of
            // silently dropping it. Log-only events without message content
            // remain out of the transcript.
            if let message = event.data["message"] {
                let text = contentText(message["content"])
                if !text.isEmpty {
                    appendNotice(
                        id: "event-\(event.seq)",
                        seq: event.seq,
                        time: event.date,
                        kind: .notice(text: "[\(event.type)] \(text)")
                    )
                }
            }
        }
        rememberFirstSeq()
    }

    private mutating func applyUserMessage(_ event: SessionWireEvent) {
        let message = event.data["message"] ?? event.data
        let sourceKind = message["source"]?["kind"]?.stringValue
        // Runtime context and time snapshots also arrive as user/message.
        // Only human-authored messages belong in the conversation transcript.
        if let sourceKind, sourceKind != "user" { return }
        let messageID = message["id"]?.stringValue
        let text = contentText(message["content"])
        guard !text.isEmpty || !contentHasImage(message["content"]) else { return }
        let id = messageID.map { "user-\($0)" } ?? "user-\(event.seq)"
        guard indexByItemID[id] == nil else { return }
        let display = text.isEmpty ? "[Image]" : text
        appendItem(ChatItem(id: id, seq: event.seq, time: event.date, kind: .user(text: display)))
    }

    private mutating func applyAssistantMessage(_ event: SessionWireEvent) {
        let message = event.data["message"] ?? event.data
        let messageID = message["id"]?.stringValue
        let content = message["content"]?.arrayValue ?? []
        let text = content.filter { $0["type"]?.stringValue == "text" }.compactMap { $0["text"]?.stringValue }.joined(separator: "\n\n")
        let reasoning = content.filter { $0["type"]?.stringValue == "reasoning" }.compactMap { $0["text"]?.stringValue }.joined(separator: "\n\n")
        let id = messageID.map { "assistant-\($0)" } ?? "assistant-\(event.seq)"

        // A committed message settles the process-local stream for that step.
        if let live, live.turn == event.data["turn"]?.intValue, live.step == event.data["step"]?.intValue {
            self.live = nil
        }

        if !text.isEmpty || !reasoning.isEmpty {
            if let index = indexByItemID[id] {
                items[index].kind = .assistant(text: text, reasoning: reasoning.isEmpty ? nil : reasoning)
            } else {
                appendItem(ChatItem(id: id, seq: event.seq, time: event.date, kind: .assistant(text: text, reasoning: reasoning.isEmpty ? nil : reasoning)))
            }
        }

        for block in content where block["type"]?.stringValue == "tool-call" {
            guard let callID = block["id"]?.stringValue else { continue }
            let name = block["name"]?.stringValue ?? ""
            let arguments = block["arguments"]?.stringValue ?? ""
            upsertTool(callID: callID, seq: event.seq, time: event.date, name: name, arguments: arguments)
        }
    }

    private mutating func applyAssistantAttempt(_ event: SessionWireEvent) {
        if let message = event.data["message"], message["content"] != nil {
            applyAssistantMessage(event)
        }
        guard let error = event.data["stream"]?.arrayValue?
            .compactMap({ $0["chunk"] })
            .first(where: { $0["type"]?.stringValue == "finish" })?["reason"]?["failure"] else { return }
        let message = error["message"]?.stringValue ?? "The model request failed."
        appendNotice(id: "attempt-error-\(event.seq)", seq: event.seq, time: event.date, kind: .error(text: message))
    }

    private mutating func applyToolCall(_ event: SessionWireEvent) {
        guard let callID = event.data["callId"]?.stringValue else { return }
        upsertTool(
            callID: callID,
            seq: event.seq,
            time: event.date,
            name: event.data["name"]?.stringValue ?? "",
            arguments: event.data["arguments"]?.stringValue ?? ""
        )
    }

    private mutating func applyToolResult(_ event: SessionWireEvent) {
        let message = event.data["message"] ?? event.data
        guard let callID = message["source"]?["callId"]?.stringValue ?? message["toolCallId"]?.stringValue else { return }
        let text = contentText(message["content"])
        let isError = message["isError"]?.boolValue == true || event.data["error"] != nil
        let errorText = event.data["error"]?["reason"]?.stringValue
        let result = text.isEmpty ? (errorText ?? "") : text
        if let index = toolIndexByCallID[callID], case var .tool(card) = items[index].kind {
            card.result = result
            card.isError = isError
            card.isComplete = true
            items[index].kind = .tool(card)
        } else {
            var card = ToolCard(callId: callID, name: "", arguments: "", result: result, isError: isError, isComplete: true)
            card.name = ""
            appendItem(ChatItem(id: "tool-\(callID)", seq: event.seq, time: event.date, kind: .tool(card)))
            toolIndexByCallID[callID] = indexByItemID["tool-\(callID)"]
        }
    }

    private mutating func applyTurnEnd(_ event: SessionWireEvent) {
        guard let kind = event.data["reason"]?["kind"]?.stringValue, kind != "completed" else { return }
        let message: String
        switch kind {
        case "aborted":
            message = "Generation stopped."
        case "error":
            message = event.data["reason"]?["error"]?["message"]?.stringValue
                ?? event.data["reason"]?["message"]?.stringValue
                ?? "The turn ended with an error."
            appendNotice(id: "turn-end-\(event.seq)", seq: event.seq, time: event.date, kind: .error(text: message))
            return
        default:
            message = "The turn ended: \(kind)."
        }
        appendNotice(id: "turn-end-\(event.seq)", seq: event.seq, time: event.date, kind: .notice(text: message))
    }

    private mutating func upsertTool(callID: String, seq: Int, time: Date, name: String, arguments: String) {
        if let index = toolIndexByCallID[callID], case var .tool(card) = items[index].kind {
            if !name.isEmpty { card.name = name }
            if !arguments.isEmpty { card.arguments = arguments }
            items[index].kind = .tool(card)
            return
        }
        let card = ToolCard(callId: callID, name: name, arguments: arguments, result: nil, isError: false, isComplete: false)
        appendItem(ChatItem(id: "tool-\(callID)", seq: seq, time: time, kind: .tool(card)))
        toolIndexByCallID[callID] = indexByItemID["tool-\(callID)"]
    }

    private mutating func appendNotice(id: String, seq: Int, time: Date, kind: ChatItem.Kind) {
        guard indexByItemID[id] == nil else { return }
        // The same failure can arrive from both assistant/attempt and turn/end.
        // Keep one readable error instead of two identical rows.
        if case let .error(newText) = kind,
           items.contains(where: {
               if case let .error(existing) = $0.kind {
                   return existing == newText || existing.contains(newText) || newText.contains(existing)
               }
               return false
           }) {
            return
        }
        appendItem(ChatItem(id: id, seq: seq, time: time, kind: kind))
    }

    private mutating func appendItem(_ item: ChatItem) {
        indexByItemID[item.id] = items.count
        items.append(item)
    }

    private mutating func rememberFirstSeq() {
        if let first = items.first?.seq {
            firstSeq = first
        } else if firstSeq == nil {
            firstSeq = lastSeq >= 0 ? lastSeq : nil
        }
    }

    /// Fold the Host's process-local assistant frames. These are presentation
    /// only; the committed assistant message remains the durable source.
    mutating func apply(assistantFrame frame: JSONValue) {
        guard let type = frame["type"]?.stringValue else { return }
        switch type {
        case "start":
            guard let attemptID = frame["attemptId"]?.stringValue else { return }
            live = LiveAssistant(
                attemptId: attemptID,
                turn: frame["turn"]?.intValue,
                step: frame["step"]?.intValue
            )
        case "chunk":
            guard let attemptID = frame["attemptId"]?.stringValue,
                  let chunk = frame["chunk"] else { return }
            if live?.attemptId != attemptID {
                live = LiveAssistant(attemptId: attemptID)
            }
            apply(chunk: chunk)
        case "end":
            live = nil
        default:
            break
        }
    }

    private mutating func applyStreamingBaseline(_ attempt: JSONValue) {
        guard let attemptID = attempt["attemptId"]?.stringValue else { return }
        live = LiveAssistant(
            attemptId: attemptID,
            turn: attempt["turn"]?.intValue,
            step: attempt["step"]?.intValue
        )
        for chunk in attempt["stream"]?.arrayValue ?? [] {
            apply(chunk: chunk)
        }
    }

    private mutating func apply(chunk value: JSONValue) {
        guard let type = value["type"]?.stringValue else { return }
        switch type {
        case "text-delta":
            live?.text += value["text"]?.stringValue ?? ""
        case "reasoning-delta":
            live?.reasoning += value["text"]?.stringValue ?? ""
        case "tool-call-delta":
            if let name = value["name"]?.stringValue, !name.isEmpty, live?.toolNames.last != name {
                live?.toolNames.append(name)
            }
        case "text-chunks":
            if let texts = value["texts"]?.arrayValue {
                live?.text += texts.compactMap(\.stringValue).joined()
            }
        case "reasoning-chunks":
            if let texts = value["texts"]?.arrayValue {
                live?.reasoning += texts.compactMap(\.stringValue).joined()
            }
        case "tool-call-chunks":
            if let name = value["name"]?.stringValue, !name.isEmpty, live?.toolNames.last != name {
                live?.toolNames.append(name)
            }
        case "block-end":
            if let block = value["block"], block["type"]?.stringValue == "text",
               live?.text.isEmpty == true, let text = block["text"]?.stringValue {
                live?.text = text
            }
        default:
            break
        }
    }

    private func contentText(_ content: JSONValue?) -> String {
        (content?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined(separator: "\n")
    }

    private func contentHasImage(_ content: JSONValue?) -> Bool {
        (content?.arrayValue ?? []).contains { $0["type"]?.stringValue == "image" }
    }
}
