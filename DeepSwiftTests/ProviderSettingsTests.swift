//
//  ProviderSettingsTests.swift
//  DeepSwiftTests
//

import Foundation
import Testing
@testable import DeepSwift

@Suite("Provider settings")
@MainActor
struct ProviderSettingsTests {
    private func namespace(
        _ name: String,
        value: [String: JSONValue],
        user: [String: JSONValue]? = nil,
        revision: Double = 7
    ) -> SettingsNamespaceView {
        SettingsNamespaceView(
            ns: name,
            autoGenerate: false,
            schema: nil,
            value: .object(value),
            base: nil,
            user: user.map(JSONValue.object),
            applies: "live",
            secrets: [],
            revision: revision
        )
    }

    nonisolated private static func mutateResponse(for namespace: SettingsNamespaceView) -> JSONValue {
        (try? JSONValue.encode(namespace)) ?? .object([:])
    }

    @Test("Provider credential references follow the official route rule")
    func credentialReference() {
        #expect(ProviderRow.derivedCredentialRef(for: "acme-gateway") == "ACME_GATEWAY_API_KEY")
        #expect(ProviderRow.derivedCredentialRef(for: "acme_gateway") == "ACME_GATEWAY_API_KEY")
        #expect(ProviderRow.derivedCredentialRef(for: "acme.gateway") == "ACME_GATEWAY_API_KEY")
    }

    @Test("Provider rows expose separate account and API-key routes")
    func providerRows() {
        let model = AppModel(bridge: MockBridgeService())
        let piNamespace = namespace("llm-pi-ai", value: [
            "providers": .object([
                "acme": .object([
                    "displayName": .string("Acme"),
                    "apiKeyEnv": .string("ACME_API_KEY"),
                    "models": .array([
                        .object(["id": .string("acme-one"), "name": .string("Acme One")])
                    ])
                ])
            ])
        ])
        model.settingsNamespaces = [
            "llm-deepseek": namespace("llm-deepseek", value: [
                "apiKeyEnv": .string("DEEPSEEK_API_KEY"),
                "models": .array([.object(["id": .string("deepseek-flash")])])
            ]),
            "llm-pi-ai": piNamespace
        ]
        model.providerCredentials = ["ACME_API_KEY": CredentialStatus(configured: true, source: "environment", writable: false)]

        let rows = model.providerRows
        #expect(rows.count == 2)
        #expect(rows[0].id == "deepseek-official")
        #expect(rows[0].layout == .deepSeek)
        #expect(rows[1].id == "acme")
        #expect(rows[1].layout == .piAI)
        #expect(rows[1].credential?.sourceLabel == "Environment")
        #expect(rows[1].modelCount == 1)
    }

    @Test("Custom provider validation rejects unusable drafts")
    func customValidation() {
        let model = AppModel(bridge: MockBridgeService())
        var draft = model.newCustomProviderDraft()
        draft.providerID = "Bad Provider"
        #expect(draft.validationError(existingProviderIDs: []) != nil)

        draft.providerID = "acme"
        draft.baseURL = "ftp://example.com"
        #expect(draft.validationError(existingProviderIDs: []) != nil)

        draft.baseURL = "https://gateway.example/v1"
        draft.models = []
        #expect(draft.validationError(existingProviderIDs: []) != nil)

        draft.models = [ModelDraft(modelID: "model-one")]
        #expect(draft.validationError(existingProviderIDs: []) == nil)
        #expect(draft.validationError(existingProviderIDs: ["acme"]) != nil)
    }

    @Test("Reasoning models require a live level and unique ids")
    func reasoningValidation() {
        let model = AppModel(bridge: MockBridgeService())
        var draft = model.newCustomProviderDraft()
        draft.providerID = "acme"
        draft.baseURL = "https://gateway.example/v1"
        draft.models = [ModelDraft(modelID: "model-one")]
        draft.models[0].reasoningEnabled = true
        draft.models[0].reasoningLevels = [ReasoningLevelDraft(level: "off", wireValue: "")]
        #expect(draft.validationError(existingProviderIDs: []) != nil)

        draft.models[0].reasoningLevels = [
            ReasoningLevelDraft(level: "low", wireValue: "low"),
            ReasoningLevelDraft(level: "low", wireValue: "low")
        ]
        #expect(draft.validationError(existingProviderIDs: []) != nil)
    }

    @Test("Selecting a BYOK model uses the session selection API")
    func selectByokModel() async throws {
        let bridge = MockBridgeService()
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-1"
        await model.selectModel(ModelSelection(
            provider: "acme-ui-test",
            model: "acme-chat",
            reasoningEffort: "high"
        ))

        let requests = await bridge.recordedRequests()
        let call = try #require(requests.last)
        #expect(call.params["namespace"]?.stringValue == "session")
        #expect(call.params["method"]?.stringValue == "selectModel")
        let request = try #require(call.params["args"]?["request"])
        #expect(request["sessionId"]?.stringValue == "session-1")
        #expect(request["provider"]?.stringValue == "acme-ui-test")
        #expect(request["model"]?.stringValue == "acme-chat")
        #expect(request["reasoningEffort"]?.stringValue == "high")
    }

    @Test("Model edits preserve unrelated catalog fields")
    func preservesModelFields() {
        let original = JSONValue.object([
            "id": .string("model-one"),
            "name": .string("Model One"),
            "description": .string("Keep me"),
            "contextWindow": .number(32_000),
            "input": .array([.string("text"), .string("image")]),
            "compat": .object(["supportsStore": .bool(true)])
        ])
        var draft = ModelDraft(json: original, layout: .piAI)
        draft.maxTokens = "4096"
        draft.includesImage = false
        let result = draft.json(layout: .piAI)
        #expect(result["description"]?.stringValue == "Keep me")
        #expect(result["compat"]?["supportsStore"]?.boolValue == true)
        #expect(result["maxTokens"]?.intValue == 4096)
        #expect(result["input"]?.arrayValue?.compactMap(\.stringValue) == ["text"])
    }

    @Test("Adding a custom provider writes settings before its credential")
    func addCustomProvider() async throws {
        let piNamespace = namespace("llm-pi-ai", value: ["providers": .object([:])])
        let bridge = MockBridgeService { method, params in
            if method == "host.call", params["method"]?.stringValue == "mutate" {
                return Self.mutateResponse(for: piNamespace)
            }
            if method == "host.call", params["method"]?.stringValue == "set" {
                return .null
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.connectionState = AppModel.ConnectionState.ready
        model.settingsNamespaces = ["llm-pi-ai": piNamespace]

        var draft = model.newCustomProviderDraft()
        draft.providerID = "acme"
        draft.displayName = "Acme Gateway"
        draft.baseURL = "https://gateway.example/v1"
        draft.models = [ModelDraft(modelID: "acme-one", name: "Acme One", contextWindow: "32768")]

        try await model.saveProvider(draft, apiKey: "sk-test-not-real")

        let requests = await bridge.recordedRequests()
        let settingsIndex = try #require(requests.firstIndex(where: { request in
            let isHostCall = request.method == "host.call"
            let isSettings = request.params["namespace"]?.stringValue == "settings"
            let isMutate = request.params["method"]?.stringValue == "mutate"
            return isHostCall && isSettings && isMutate
        }))
        let credentialIndex = try #require(requests.firstIndex(where: { request in
            let isHostCall = request.method == "host.call"
            let isCredentials = request.params["namespace"]?.stringValue == "credentials"
            let isSet = request.params["method"]?.stringValue == "set"
            return isHostCall && isCredentials && isSet
        }))
        #expect(settingsIndex < credentialIndex)

        let mutation = requests[settingsIndex].params["args"]
        #expect(mutation?["ns"]?.stringValue == "llm-pi-ai")
        #expect(mutation?["expectedRevision"]?.intValue == 7)
        let op = try #require(mutation?["ops"]?[0])
        #expect(op["op"]?.stringValue == "set")
        #expect(op["path"]?.arrayValue?.compactMap { $0.stringValue } == ["providers", "acme"])
        #expect(op["value"]?["api"]?.stringValue == "openai-completions")
        #expect(op["value"]?["baseURL"]?.stringValue == "https://gateway.example/v1")
        #expect(op["value"]?["apiKeyEnv"]?.stringValue == "ACME_API_KEY")

        let credential = requests[credentialIndex].params["args"]
        #expect(credential?["ref"]?.stringValue == "ACME_API_KEY")
        #expect(credential?["value"]?.stringValue == "sk-test-not-real")
    }

    @Test("Adding a built-in provider writes only its activation profile")
    func addBuiltInProvider() async throws {
        let piNamespace = namespace("llm-pi-ai", value: ["providers": .object([:])])
        let entry = ConfigurableProvider(
            provider: "openai",
            displayName: "OpenAI",
            settingsNs: "llm-pi-ai",
            settingsPath: ["providers", "openai"],
            declared: false,
            defaultBaseURL: "https://api.openai.com/v1",
            baseURLEnv: nil,
            nativeAuth: .init(env: ["OPENAI_API_KEY"], oauth: false),
            error: nil
        )
        let bridge = MockBridgeService { method, params in
            if method == "host.call", params["method"]?.stringValue == "mutate" {
                return Self.mutateResponse(for: piNamespace)
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.connectionState = AppModel.ConnectionState.ready
        model.settingsNamespaces = ["llm-pi-ai": piNamespace]
        model.providerDirectory = [entry]

        var draft = model.newBuiltInProviderDraft(for: entry)
        draft.displayName = "OpenAI"
        try await model.saveProvider(draft, apiKey: "sk-test-not-real")

        let requests = await bridge.recordedRequests()
        let mutation = try #require(requests.first(where: { request in
            request.params["method"]?.stringValue == "mutate"
        })?.params["args"])
        let op = try #require(mutation["ops"]?[0])
        #expect(op["op"]?.stringValue == "set")
        #expect(op["path"]?.arrayValue?.compactMap { $0.stringValue } == ["providers", "openai"])
        #expect(op["value"]?["apiKeyEnv"]?.stringValue == "OPENAI_API_KEY")
        #expect(op["value"]?["models"] == nil)
        #expect(op["value"]?["api"] == nil)
    }

    @Test("DeepSeek API key writes the direct provider and its managed reference")
    func saveDeepSeekProvider() async throws {
        let deepSeekNamespace = namespace("llm-deepseek", value: [
            "apiKeyEnv": .string("DEEPSEEK_API_KEY"),
            "models": .array([.object(["id": .string("deepseek-flash")])])
        ])
        let bridge = MockBridgeService { method, params in
            if method == "host.call", params["method"]?.stringValue == "mutate" {
                return Self.mutateResponse(for: deepSeekNamespace)
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.connectionState = AppModel.ConnectionState.ready
        model.settingsNamespaces = ["llm-deepseek": deepSeekNamespace]
        guard let row = model.providerRows.first else {
            Issue.record("Missing DeepSeek provider row")
            return
        }
        let draft = model.providerDraft(for: row)
        try await model.saveProvider(draft, apiKey: "sk-test-not-real")

        let requests = await bridge.recordedRequests()
        let mutation = try #require(requests.first(where: { request in
            request.params["method"]?.stringValue == "mutate"
        })?.params["args"])
        #expect(mutation["ns"]?.stringValue == "llm-deepseek")
        let operations = try #require(mutation["ops"]?.arrayValue)
        let paths = operations.compactMap { $0["path"]?.arrayValue?.compactMap { $0.stringValue } }
        #expect(paths.contains(["apiKeyEnv"]))
        #expect(paths.contains(["baseURL"]))
        let credential = try #require(requests.first(where: { request in
            request.params["method"]?.stringValue == "set"
        })?.params["args"])
        #expect(credential["ref"]?.stringValue == "DEEPSEEK_API_KEY")
    }

    @Test("Editing a provider mutates fields without replacing other providers")
    func editProviderPreservesOthers() async throws {
        let piNamespace = namespace("llm-pi-ai", value: ["providers": .object([:])])
        let bridge = MockBridgeService { method, params in
            if method == "host.call", params["method"]?.stringValue == "mutate" {
                return Self.mutateResponse(for: piNamespace)
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.connectionState = AppModel.ConnectionState.ready
        model.settingsNamespaces = ["llm-pi-ai": piNamespace]
        var draft = model.newCustomProviderDraft()
        draft.providerID = "acme"
        draft.displayName = "Acme"
        draft.baseURL = "https://gateway.example/v1"
        draft.models = [ModelDraft(modelID: "one")]
        draft.isNew = false

        try await model.saveProvider(draft, apiKey: "")

        let requests = await bridge.recordedRequests()
        let mutation = try #require(requests.first(where: { request in
            request.params["method"]?.stringValue == "mutate"
        })?.params["args"])
        let paths = mutation["ops"]?.arrayValue?.compactMap { item in item["path"]?.arrayValue?.compactMap { $0.stringValue } } ?? []
        #expect(paths.contains(["providers", "acme", "baseURL"]))
        #expect(!paths.contains(["providers"]))
    }

    @Test("Deleting a provider removes only its path and managed credential")
    func removeProvider() async throws {
        let piNamespace = namespace("llm-pi-ai", value: [
            "providers": .object([
                "acme": .object([
                    "displayName": .string("Acme"),
                    "apiKeyEnv": .string("ACME_API_KEY"),
                    "models": .array([.object(["id": .string("one")])])
                ])
            ])
        ])
        let bridge = MockBridgeService { method, params in
            if method == "host.call", params["method"]?.stringValue == "mutate" {
                return Self.mutateResponse(for: piNamespace)
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.connectionState = AppModel.ConnectionState.ready
        model.settingsNamespaces = ["llm-pi-ai": piNamespace]
        model.providerCredentials = ["ACME_API_KEY": CredentialStatus(configured: true, source: "file", writable: true)]
        let row = try #require(model.providerRows.first { $0.id == "acme" })

        try await model.removeProvider(row)

        let requests = await bridge.recordedRequests()
        let mutation = try #require(requests.first(where: { request in
            request.params["method"]?.stringValue == "mutate"
        })?.params["args"])
        let op = try #require(mutation["ops"]?[0])
        #expect(op["op"]?.stringValue == "unset")
        #expect(op["path"]?.arrayValue?.compactMap { $0.stringValue } == ["providers", "acme"])
        let unsetRequest = try #require(requests.first(where: { request in
            request.params["method"]?.stringValue == "unset"
        })?.params["args"])
        #expect(unsetRequest["ref"]?.stringValue == "ACME_API_KEY")
    }

    @Test("Credential failures never echo the submitted secret")
    func redactsCredentialFailure() async throws {
        let piNamespace = namespace("llm-pi-ai", value: ["providers": .object([:])])
        let secret = "sk-private-test-value"
        let bridge = MockBridgeService { method, params in
            if method == "host.call", params["method"]?.stringValue == "mutate" {
                return Self.mutateResponse(for: piNamespace)
            }
            if method == "host.call", params["method"]?.stringValue == "set" {
                throw BridgeClientError.bridge(
                    code: "credentials/rejected",
                    message: "The credential \(secret) was rejected",
                    details: nil
                )
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        model.connectionState = AppModel.ConnectionState.ready
        model.settingsNamespaces = ["llm-pi-ai": piNamespace]
        var draft = model.newCustomProviderDraft()
        draft.providerID = "acme"
        draft.baseURL = "https://gateway.example/v1"
        draft.models = [ModelDraft(modelID: "one")]

        do {
            try await model.saveProvider(draft, apiKey: secret)
            Issue.record("Expected the credential write to fail")
        } catch {
            #expect(!error.localizedDescription.contains(secret))
            #expect(error.localizedDescription.contains("••••••"))
        }
        #expect(model.providerError?.contains(secret) == false)
    }

    @Test("Model discovery sends only the official request shape")
    func discoverModels() async throws {
        let bridge = MockBridgeService { method, params in
            if method == "host.call", params["method"]?.stringValue == "discoverModels" {
                return .array([
                    .object([
                        "id": .string("model-one"),
                        "name": .string("Model One"),
                        "contextWindow": .number(32_000),
                        "inputModalities": .array([.string("text"), .string("image")])
                    ])
                ])
            }
            return .object([:])
        }
        let model = AppModel(bridge: bridge)
        let results = try await model.discoverModels(
            settingsNamespace: "llm-pi-ai",
            provider: nil,
            baseURL: "https://gateway.example/v1",
            api: "openai-completions",
            apiKey: "sk-test-not-real"
        )
        #expect(results.count == 1)
        #expect(results[0].draft.includesImage)

        let requests = await bridge.recordedRequests()
        let args = try #require(requests.first?.params["args"])
        #expect(args["settingsNs"]?.stringValue == "llm-pi-ai")
        #expect(args["request"]?["baseURL"]?.stringValue == "https://gateway.example/v1")
        #expect(args["request"]?["api"]?.stringValue == "openai-completions")
    }

    @Test("Environment credential status is displayed without a value")
    func environmentCredential() {
        let status = CredentialStatus(configured: true, source: "environment", writable: false)
        #expect(status.sourceLabel == "Environment")
        #expect(status.configured)
        #expect(!status.isWritable)
    }
}
