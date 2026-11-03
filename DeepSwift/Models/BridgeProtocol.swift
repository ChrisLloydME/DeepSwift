//
//  BridgeProtocol.swift
//  DeepSwift
//

import Foundation

/// Version of the stdio protocol implemented by `Bridge/src/main.mjs`.
enum BridgeProtocol {
    static let version = 1
}

nonisolated struct BridgeRequest: Encodable, Sendable {
    let id: String
    let method: String
    let params: JSONValue
}

nonisolated struct BridgeNotification: Sendable {
    let event: String
    let data: JSONValue
}

nonisolated struct BridgeResponseEnvelope: Decodable, Sendable {
    let id: String?
    let result: JSONValue?
    let error: BridgeResponseError?
}

nonisolated struct BridgeResponseError: Decodable, Sendable {
    let code: String
    let message: String
    let details: JSONValue?
}

enum BridgeClientError: LocalizedError, Sendable {
    case notRunning
    case launchFailed(String)
    case transportClosed(String)
    case timedOut(String)
    case protocolViolation(String)
    case bridge(code: String, message: String, details: JSONValue?)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "The local DSH bridge is not running."
        case let .launchFailed(message):
            return message
        case let .transportClosed(message):
            return message
        case let .timedOut(method):
            return "The bridge did not answer \(method) in time."
        case let .protocolViolation(message):
            return message
        case let .bridge(_, message, _):
            return message
        }
    }

    var code: String {
        switch self {
        case .notRunning: return "bridge/not-running"
        case .launchFailed: return "bridge/launch-failed"
        case .transportClosed: return "bridge/transport-closed"
        case .timedOut: return "bridge/timeout"
        case .protocolViolation: return "bridge/protocol"
        case let .bridge(code, _, _): return code
        }
    }

    /// The nested detail object the Host attaches to a Remote failure.
    var hostDetails: JSONValue? {
        guard case let .bridge(_, _, details) = self else { return nil }
        return details?["details"]
    }
}
