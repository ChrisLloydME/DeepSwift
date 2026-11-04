//
//  BridgeClientIntegrationTests.swift
//  DeepSwiftTests
//

import Foundation
import Testing
@testable import DeepSwift

@Suite("Bridge client framing")
struct BridgeClientIntegrationTests {
    private static let script = #"""
    import json
    import sys
    import time

    for line in sys.stdin:
        try:
            request = json.loads(line)
        except Exception:
            continue
        method = request.get("method")
        request_id = request.get("id")
        if method == "large":
            models = []
            for index in range(120):
                models.append({
                    "id": "synthetic-model-" + str(index),
                    "contextWindow": 128000,
                    "maxTokens": 16384,
                    "apiKeyEnv": "DEEPSEEK_API_KEY",
                    "meta": {"index": index, "kind": "synthetic"}
                })
            result = {
                "type": "configuration",
                "meta": {"schemaVersion": 3},
                "refs": [{"namespace": "llm-pi-ai", "revision": 7}],
                "providers": {"opencode-go": {"models": models}},
                "models": models
            }
            frame = json.dumps({"id": request_id, "result": result}, separators=(",", ":")) + "\n"
            # Deliberately spread the frame across many reads. The client must
            # preserve byte order even when the pipe yields small chunks.
            for offset in range(0, len(frame), 1024):
                sys.stdout.write(frame[offset:offset + 1024])
                sys.stdout.flush()
                time.sleep(0.001)
        elif method == "malformed":
            sys.stdout.write(json.dumps({"id": request_id, "error": "not-an-object"}) + "\n")
            sys.stdout.flush()
        elif method == "shutdown":
            sys.stdout.write(json.dumps({"id": request_id, "result": {"accepted": True}}) + "\n")
            sys.stdout.flush()
            break
        else:
            sys.stdout.write(json.dumps({"id": request_id, "error": {"code": "test/unknown", "message": "unknown"}}) + "\n")
            sys.stdout.flush()
    """#

    @Test("A valid large response split across pipe reads arrives intact")
    func largeResponse() async throws {
        let bridge = BridgeClient()
        let (configuration, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await bridge.start(configuration: configuration)
        do {
            let value = try await bridge.request("large", timeout: .seconds(10))
            #expect(value["type"]?.stringValue == "configuration")
            #expect(value["refs"]?.arrayValue?.count == 1)
            let models = value["providers"]?["opencode-go"]?["models"]?.arrayValue
            #expect(models?.count == 120)
            #expect(models?.first?["contextWindow"]?.intValue == 128_000)
        } catch {
            let tail = await bridge.stderrTail
            await bridge.stop()
            Issue.record("large response failed: \(error); stderr: \(tail)")
            throw error
        }
        await bridge.stop()
    }

    @Test("A malformed response with a parsed id fails its pending request promptly")
    func malformedResponseFailsPendingRequest() async throws {
        let bridge = BridgeClient()
        let (configuration, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await bridge.start(configuration: configuration)
        do {
            _ = try await bridge.request("malformed", timeout: .seconds(5))
            Issue.record("Expected a protocol failure")
        } catch let error as BridgeClientError {
            #expect(error.code == "bridge/protocol")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await bridge.stop()
    }

    private func makeConfiguration() throws -> (RuntimeConfiguration, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSwift-bridge-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("fake-bridge.py")
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let wrapperURL = directory.appendingPathComponent("fake-bridge.sh")
        let wrapper = """
        #!/bin/sh
        export LANG=C.UTF-8
        export LC_ALL=C.UTF-8
        exec /usr/bin/python3 "$(dirname "$0")/fake-bridge.py"
        """
        try wrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        return (
            RuntimeConfiguration(
                nodePath: "/bin/sh",
                dshBinPath: "/bin/true",
                bridgePath: wrapperURL.path,
                dshHome: directory.path,
                allowProviderEnv: false
            ),
            directory
        )
    }
}
