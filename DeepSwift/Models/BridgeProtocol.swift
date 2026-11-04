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

/// Decoded shape for every bridge-to-Swift stdout frame.
///
/// Kept separate from request envelopes so one type can validate both events
/// and responses. All payload values remain `JSONValue`; only the envelope is
/// typed.
nonisolated struct BridgeInboundEnvelope: Decodable, Sendable {
    let id: String?
    let result: JSONValue?
    let error: BridgeResponseError?
    let event: String?
    let data: JSONValue?
}

/// Newline-delimited frame accumulator with an explicit incomplete-frame cap.
///
/// The bridge is a line protocol. Keeping framing in one value object makes
/// split reads, multiple frames per read, and oversized unterminated frames
/// deterministic and testable.
struct BridgeFrameBuffer: Sendable {
    private(set) var buffer = Data()
    let maximumBufferedBytes: Int

    init(maximumBufferedBytes: Int = 64 * 1024 * 1024) {
        self.maximumBufferedBytes = maximumBufferedBytes
    }

    var bufferedByteCount: Int { buffer.count }

    mutating func append(_ chunk: Data) -> [Data] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)
        var frames: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            frames.append(Data(line))
        }
        return frames
    }

    /// Discards one unterminated frame that exceeded the cap. Returns its byte
    /// count so callers can report a bounded diagnostic without retaining the
    /// payload.
    mutating func discardOversizedFrame() -> Int? {
        guard buffer.count > maximumBufferedBytes else { return nil }
        let count = buffer.count
        buffer.removeAll(keepingCapacity: false)
        return count
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
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
