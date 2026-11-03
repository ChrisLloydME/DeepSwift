//
//  JSONValueTests.swift
//  DeepSwiftTests
//

import Foundation
import Testing
@testable import DeepSwift

@Suite("JSON value")
struct JSONValueTests {
    @Test("Round-trips every JSON shape")
    func roundTrip() throws {
        let original = JSONValue.object([
            "string": .string("value"),
            "number": .number(42),
            "double": .number(1.5),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.number(1), .string("two")]),
            "nested": .object(["key": .string("nested")])
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
        #expect(decoded["number"]?.intValue == 42)
        #expect(decoded["double"]?.doubleValue == 1.5)
        #expect(decoded["array"]?[1]?.stringValue == "two")
    }

    @Test("Typed decode uses Foundation models")
    func typedDecode() throws {
        struct Model: Codable, Equatable {
            let name: String
            let count: Int
        }
        let value = JSONValue.object(["name": .string("DSH"), "count": .number(3)])
        let model = try value.decode(Model.self)
        #expect(model == Model(name: "DSH", count: 3))
    }

    @Test("Bridge error details stay nested")
    func errorDetails() {
        let error = BridgeClientError.bridge(
            code: "host/session/not-found",
            message: "missing",
            details: .object(["details": .object(["sessionId": .string("s1")])])
        )
        #expect(error.code == "host/session/not-found")
        #expect(error.hostDetails?["sessionId"]?.stringValue == "s1")
    }
}
