//
//  AppErrorPresentation.swift
//  DeepSwift
//

import Foundation

/// A bounded, sanitized error suitable for the application's alert boundary.
///
/// Raw protocol frames, settings documents, stderr, and response bodies never
/// enter this type. Technical details are optional, size-limited, and already
/// redacted by `AppErrorPresentationFactory`.
struct AppErrorPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let message: String
    let recovery: String?
    let code: String
    let diagnosticID: String
    let technicalDetails: String?

    var hasDetails: Bool {
        !(technicalDetails?.isEmpty ?? true)
    }

    var alertMessage: String {
        [message, recovery]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var diagnosticText: String {
        var lines = [
            "DeepSwift diagnostic \(diagnosticID)",
            "Code: \(code)",
            "Title: \(title)",
            "Message: \(message)"
        ]
        if let recovery, !recovery.isEmpty {
            lines.append("Recovery: \(recovery)")
        }
        if let technicalDetails, !technicalDetails.isEmpty {
            lines.append("")
            lines.append(technicalDetails)
        }
        return lines.joined(separator: "\n")
    }
}

/// Centralized error sanitization and user-facing classification.
///
/// This is deliberately conservative: it preserves short, meaningful server
/// explanations, but discards anything that resembles a serialized document,
/// credential value, or arbitrary payload.
enum AppErrorPresentationFactory {
    private static let messageLimit = 320
    private static let detailLimit = 8_000

    static func make(
        error: Error,
        action: String,
        recovery: String? = nil
    ) -> AppErrorPresentation {
        if let bridge = error as? BridgeClientError {
            return make(bridge: bridge, action: action, recovery: recovery)
        }
        if let provider = error as? ProviderSettingsError {
            let summary = summary(provider.message) ?? "The provider settings request did not complete."
            return make(
                title: "Provider settings couldn’t be updated",
                message: summary,
                recovery: recovery ?? "Review the provider fields and try again.",
                code: "provider/settings",
                action: action,
                details: compactDetails(code: "provider/settings", action: action, reason: summary)
            )
        }
        if error is DecodingError {
            return make(
                title: "DeepSwift couldn’t read the runtime response",
                message: "A response from the local runtime did not match the expected format.",
                recovery: recovery ?? "Retry the action. If it keeps happening, restart the runtime from Settings > General.",
                code: "app/decoding",
                action: action,
                details: compactDetails(code: "app/decoding", action: action, reason: decodingReason(error))
            )
        }

        let raw = error.localizedDescription
        let safe = summary(raw)
        let message = safe ?? "The request did not complete."
        return make(
            title: "DeepSwift couldn’t complete that action",
            message: message,
            recovery: recovery,
            code: "app/error",
            action: action,
            details: compactDetails(code: "app/error", action: action, reason: safe)
        )
    }

    static func make(
        title: String = "DeepSwift couldn’t complete that action",
        message rawMessage: String?,
        recovery: String? = nil,
        code: String,
        action: String,
        details: String? = nil
    ) -> AppErrorPresentation {
        let safeMessage = summary(rawMessage ?? "")
            ?? "The request did not complete. No internal details were retained."
        let safeCode = summary(code, limit: 80) ?? "app/error"
        let baseDetails = details ?? compactDetails(
            code: safeCode,
            action: action,
            reason: nil
        )
        let safeDetails = baseDetails.flatMap { sanitizedDetails($0) }
        return AppErrorPresentation(
            id: UUID(),
            title: summary(title, limit: 120) ?? "DeepSwift",
            message: safeMessage,
            recovery: summary(recovery ?? "", limit: 240),
            code: safeCode,
            diagnosticID: newDiagnosticID(),
            technicalDetails: safeDetails
        )
    }

    /// Short, safe text for inline error labels and secondary presentation.
    static func summary(_ raw: String, limit: Int = messageLimit) -> String? {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Never promote a serialized document into an alert or inline label.
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return nil
        }
        if text.contains("apiKeyEnv")
            || text.contains("contextWindow")
            || (text.contains("providers") && text.contains("models") && text.contains(":")) {
            return nil
        }

        // Keep useful prose that precedes an embedded payload, but discard the
        // payload itself.
        if let payloadStart = text.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            let prefix = text[..<payloadStart].trimmingCharacters(in: .whitespacesAndNewlines)
            text = prefix.isEmpty ? "" : String(prefix)
        }

        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                guard !line.hasPrefix("{"), !line.hasPrefix("["), !line.hasPrefix("\"") else { return false }
                return true
            }
        text = lines.joined(separator: " ")
        text = redact(text)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.count > limit {
            let bounded = String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
            text = bounded + "…"
        }
        return text
    }

    /// Sanitized, bounded diagnostics for a native details sheet.
    static func sanitizedDetails(_ raw: String, limit: Int = detailLimit) -> String? {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            var value = line
            if let payloadStart = value.firstIndex(where: { $0 == "{" || $0 == "[" }) {
                value = String(value[..<payloadStart])
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("\""), !trimmed.hasPrefix("{"), !trimmed.hasPrefix("[") else { continue }
            guard !trimmed.contains("apiKeyEnv"), !trimmed.contains("contextWindow") else { continue }
            lines.append(trimmed)
        }
        var cleaned = redact(lines.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        // A serialized document can be formatted as one long line; never let
        // it through merely because it did not begin with a brace.
        if cleaned.contains("apiKeyEnv")
            || cleaned.contains("contextWindow")
            || (cleaned.contains("providers") && cleaned.contains("models") && cleaned.contains(":")) {
            return nil
        }
        if cleaned.count <= limit { return cleaned }
        cleaned = String(cleaned.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned + "\n… details truncated"
    }

    static func redact(_ raw: String) -> String {
        var text = raw
        let patterns: [(pattern: String, replacement: String)] = [
            (#"(?i)\bsk-[A-Za-z0-9_-]{8,}\b"#, "sk-••••"),
            (#"\b[A-Za-z0-9_-]{32,}\b"#, "••••"),
            (#"(?i)(bearer\s+)[^\s,;]+"#, "$1••••"),
            (#"(?i)((?:api[_-]?key|access[_-]?token|authorization|secret|password)\s*[:=]\s*)[^\s,;]+"#, "$1••••"),
            (#"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#, "$1••••@")
        ]
        for (pattern, replacement) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = expression.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: replacement
            )
        }
        return text
    }

    private static func make(
        bridge: BridgeClientError,
        action: String,
        recovery: String?
    ) -> AppErrorPresentation {
        let title: String
        let message: String
        let defaultRecovery: String?
        let code = bridge.code
        let reason: String?

        switch bridge {
        case .notRunning:
            title = "The local runtime isn’t running"
            message = "DeepSwift could not reach the local DSH runtime."
            defaultRecovery = "Start or restart the runtime from Settings > General, then try again."
            reason = nil
        case let .launchFailed(detail):
            title = "DeepSwift couldn’t start the local runtime"
            message = "The local bridge could not be launched."
            defaultRecovery = "Check the runtime paths in Settings > General and try again."
            reason = summary(detail)
        case let .transportClosed(detail):
            title = "The local runtime connection closed"
            message = "The runtime stopped while DeepSwift was waiting for a response."
            defaultRecovery = "Restart the runtime from Settings > General, then retry."
            reason = summary(detail)
        case let .timedOut(method):
            title = "The runtime took too long to respond"
            message = "The local runtime did not answer \(safeMethod(method)) in time."
            defaultRecovery = "Try again. The operation may still be running in the runtime."
            reason = nil
        case let .protocolViolation(detail):
            title = "DeepSwift couldn’t read a response from the local runtime"
            message = "The local runtime returned a response DeepSwift could not decode."
            defaultRecovery = "Retry the action. If it keeps happening, restart the runtime from Settings > General."
            reason = summary(detail)
        case let .bridge(_, hostMessage, _):
            title = "The runtime rejected the request"
            message = summary(hostMessage) ?? "The local runtime could not complete the request."
            defaultRecovery = recovery ?? "Review the request and try again."
            reason = summary(hostMessage)
        }

        return AppErrorPresentation(
            id: UUID(),
            title: title,
            message: message,
            recovery: defaultRecovery,
            code: summary(code, limit: 80) ?? "bridge/error",
            diagnosticID: newDiagnosticID(),
            technicalDetails: compactDetails(code: code, action: action, reason: reason)
        )
    }

    private static func compactDetails(code: String, action: String, reason: String?) -> String? {
        var lines = [
            "Code: \(summary(code, limit: 80) ?? "app/error")",
            "Action: \(summary(action, limit: 160) ?? "request")"
        ]
        if let reason, !reason.isEmpty {
            lines.append("Reason: \(reason)")
        }
        return sanitizedDetails(lines.joined(separator: "\n"))
    }

    private static func decodingReason(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return "The response format was not recognized."
        }
        switch decoding {
        case let .keyNotFound(key, context):
            return "Missing field \(codingPath(context.codingPath + [key]))"
        case let .typeMismatch(_, context):
            return "Unexpected type at \(codingPath(context.codingPath))"
        case let .valueNotFound(_, context):
            return "Missing value at \(codingPath(context.codingPath))"
        case .dataCorrupted:
            return "Malformed response data"
        @unknown default:
            return "The response format was not recognized."
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "the response root" }
        return path.map(\.stringValue).joined(separator: ".")
    }

    private static func safeMethod(_ method: String) -> String {
        summary(method, limit: 80) ?? "the request"
    }

    private static func newDiagnosticID() -> String {
        "DS-" + UUID().uuidString.prefix(8).uppercased()
    }
}
