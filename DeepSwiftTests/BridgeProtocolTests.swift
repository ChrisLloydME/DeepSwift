//
//  BridgeProtocolTests.swift
//  DeepSwiftTests
//

import Foundation
import Testing
@testable import DeepSwift

@Suite("Bridge protocol framing")
struct BridgeProtocolTests {
    private func configEnvelope(id: String = "large") throws -> Data {
        let config: JSONValue = .object([
            "type": .string("configuration"),
            "meta": .object([
                "schemaVersion": .number(3),
                "source": .string("synthetic-fixture")
            ]),
            "refs": .array([
                .object(["namespace": .string("llm-pi-ai"), "revision": .number(7)])
            ]),
            "providers": .object([
                "opencode-go": .object([
                    "apiKeyEnv": .string("DEEPSEEK_API_KEY"),
                    "models": .array([
                        .object([
                            "id": .string("synthetic-model"),
                            "contextWindow": .number(128_000),
                            "maxTokens": .number(16_384)
                        ])
                    ])
                ])
            ])
        ])
        return try JSONEncoder().encode(BridgeInboundEnvelopeForEncoding(id: id, result: config))
    }

    @Test("A large valid frame split across many reads decodes intact")
    func splitLargeFrame() throws {
        let frame = try configEnvelope()
        var buffer = BridgeFrameBuffer()
        var frames: [Data] = []
        let line = frame + Data([0x0A])
        for chunk in line.chunks(of: 7) {
            frames.append(contentsOf: buffer.append(chunk))
        }

        #expect(frames.count == 1)
        #expect(buffer.bufferedByteCount == 0)
        let decoded = try JSONDecoder().decode(BridgeInboundEnvelope.self, from: try #require(frames.first))
        #expect(decoded.id == "large")
        #expect(decoded.event == nil)
        #expect(decoded.result?["providers"]?["opencode-go"]?["models"]?.arrayValue?.count == 1)
        #expect(decoded.result?["providers"]?["opencode-go"]?["models"]?[0]?["contextWindow"]?.intValue == 128_000)
    }

    @Test("Multiple complete frames in one read remain ordered")
    func multipleFramesOneRead() throws {
        let first = try configEnvelope(id: "first")
        let second = try configEnvelope(id: "second")
        var buffer = BridgeFrameBuffer()
        let frames = buffer.append(first + Data([0x0A]) + second + Data([0x0A]))

        #expect(frames.count == 2)
        let ids = try frames.map { try JSONDecoder().decode(BridgeInboundEnvelope.self, from: $0).id }
        #expect(ids == ["first", "second"])
    }

    @Test("An incomplete frame is retained until its newline arrives")
    func incompleteFrame() throws {
        var buffer = BridgeFrameBuffer()
        let frame = try configEnvelope()
        #expect(buffer.append(frame.prefix(frame.count / 2)).isEmpty)
        #expect(buffer.bufferedByteCount == frame.count / 2)
        let frames = buffer.append(frame.suffix(frame.count - frame.count / 2) + Data([0x0A]))
        #expect(frames.count == 1)
    }

    @Test("An oversized unterminated frame is discarded without retaining data")
    func oversizedFrame() throws {
        var buffer = BridgeFrameBuffer(maximumBufferedBytes: 64)
        _ = buffer.append(Data(repeating: 0x41, count: 100))
        #expect(buffer.discardOversizedFrame() == 100)
        #expect(buffer.bufferedByteCount == 0)
        #expect(buffer.discardOversizedFrame() == nil)
    }

    @Test("Malformed JSON is not accepted as an envelope")
    func malformedJSON() {
        let data = Data("{not-json".utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeInboundEnvelope.self, from: data)
        }
    }
}

private struct BridgeInboundEnvelopeForEncoding: Encodable {
    let id: String
    let result: JSONValue
}

private extension Data {
    func chunks(of size: Int) -> [Data] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: startIndex, to: endIndex, by: size).map {
            let end = index($0, offsetBy: size, limitedBy: endIndex) ?? endIndex
            return self[$0..<end]
        }
    }
}
