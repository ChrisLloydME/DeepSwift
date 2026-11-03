//
//  ProviderModels.swift
//  DeepSwift
//

import Foundation

struct ProviderSettingsError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Official settings and provider directory

struct SettingsSecretSlot: Codable, Hashable, Sendable {
    let path: [String]
    let set: Bool
}

struct SettingsNamespaceView: Codable, Sendable {
    let ns: String
    let autoGenerate: Bool?
    let schema: JSONValue?
    let value: JSONValue
    let base: JSONValue?
    let user: JSONValue?
    let applies: String?
    let secrets: [SettingsSecretSlot]?
    let revision: Double
}

struct SettingsDescription: Codable, Sendable {
    let writable: Bool
    let hasDocument: Bool
    let namespaces: [SettingsNamespaceView]

    var byNamespace: [String: SettingsNamespaceView] {
        Dictionary(uniqueKeysWithValues: namespaces.map { ($0.ns, $0) })
    }
}

struct ConfigurableProvider: Codable, Identifiable, Hashable, Sendable {
    struct NativeAuth: Codable, Hashable, Sendable {
        let env: [String]
        let oauth: Bool
    }

    let provider: String
    let displayName: String
    let settingsNs: String
    let settingsPath: [String]
    let declared: Bool?
    let defaultBaseURL: String?
    let baseURLEnv: [String]?
    let nativeAuth: NativeAuth?
    let error: String?

    var id: String { provider }
    var isCustomRoute: Bool { declared == true }
}

struct CredentialStatus: Codable, Hashable, Sendable {
    let configured: Bool
    let source: String?
    let writable: Bool?

    var sourceLabel: String {
        guard configured else { return "Not configured" }
        switch source {
        case "file": return "Stored in DSH"
        case "environment": return "Environment"
        case "project-env": return "Project .env"
        case "home-env": return "Profile .env"
        case let value?: return value.replacingOccurrences(of: "-", with: " ").capitalized
        case nil: return "Configured"
        }
    }

    var isWritable: Bool { writable == true }
}

// MARK: - Provider selection

enum ProviderLayout: String, Sendable {
    case deepSeek
    case piAI
}

enum ProviderProtocol: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAICompletions = "openai-completions"
    case openAIResponses = "openai-responses"
    case anthropicMessages = "anthropic-messages"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompletions: "OpenAI Chat Completions"
        case .openAIResponses: "OpenAI Responses"
        case .anthropicMessages: "Anthropic Messages"
        }
    }

    var endpointPlaceholder: String {
        switch self {
        case .openAICompletions, .openAIResponses: "https://gateway.example/v1"
        case .anthropicMessages: "https://gateway.example"
        }
    }
}

struct ProviderRow: Identifiable, Sendable {
    let id: String
    let displayName: String
    let layout: ProviderLayout
    let isCustom: Bool
    let isConfigured: Bool
    let settingsNamespace: String
    let settingsRevision: Double
    let apiKeyEnv: String?
    let credential: CredentialStatus?
    let nativeAuthEnv: [String]
    let defaultBaseURL: String?
    let baseURLEnv: [String]
    let effectiveModels: [JSONValue]
    let modelCount: Int
    let error: String?
    let userProfile: JSONValue?
    let effectiveProfile: JSONValue?

    var credentialRef: String? {
        apiKeyEnv ?? Self.derivedCredentialRef(for: id)
    }

    static func derivedCredentialRef(for provider: String) -> String {
        let normalized = provider.uppercased().map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "_"
        }
        return String(normalized) + "_API_KEY"
    }
}

// MARK: - Editable drafts

struct ReasoningLevelDraft: Identifiable, Hashable, Sendable {
    let id = UUID()
    var level: String
    var wireValue: String

    init(level: String, wireValue: String) {
        self.level = level
        self.wireValue = wireValue
    }
}

struct ModelDraft: Identifiable, Hashable, Sendable {
    let id = UUID()
    static let standardReasoningLevels = ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
    static let defaultReasoningLevels = ["low", "medium", "high"]

    var modelID: String
    var name: String
    var contextWindow: String
    var maxTokens: String
    var includesText: Bool
    var includesImage: Bool
    var reasoningEnabled: Bool
    var reasoningLevels: [ReasoningLevelDraft]
    var baseJSON: JSONValue?

    init(
        modelID: String = "",
        name: String = "",
        contextWindow: String = "",
        maxTokens: String = "",
        includesText: Bool = true,
        includesImage: Bool = false,
        reasoningEnabled: Bool = false,
        reasoningLevels: [ReasoningLevelDraft] = [],
        baseJSON: JSONValue? = nil
    ) {
        self.modelID = modelID
        self.name = name
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
        self.includesText = includesText
        self.includesImage = includesImage
        self.reasoningEnabled = reasoningEnabled
        self.reasoningLevels = reasoningLevels
        self.baseJSON = baseJSON
    }

    init(json: JSONValue, layout: ProviderLayout) {
        let object = json.objectValue ?? [:]
        self.modelID = object["id"]?.stringValue ?? ""
        self.name = object["name"]?.stringValue ?? ""
        self.contextWindow = object["contextWindow"]?.intValue.map(String.init) ?? ""
        self.maxTokens = object["maxTokens"]?.intValue.map(String.init) ?? ""

        let modalities = (object[layout == .deepSeek ? "inputModalities" : "input"]?.arrayValue
            ?? object["input"]?.arrayValue
            ?? object["inputModalities"]?.arrayValue)?
            .compactMap(\.stringValue) ?? []
        self.includesText = modalities.isEmpty || modalities.contains("text")
        self.includesImage = modalities.contains("image")

        if let efforts = object["reasoningEfforts"] {
            if case let .bool(enabled) = efforts {
                self.reasoningEnabled = enabled
                self.reasoningLevels = enabled ? Self.defaultReasoningLevels.map {
                    ReasoningLevelDraft(level: $0, wireValue: $0)
                } : []
            } else if let values = efforts.objectValue {
                self.reasoningEnabled = !values.isEmpty
                self.reasoningLevels = values.keys
                    .sorted { Self.reasoningSortIndex($0) < Self.reasoningSortIndex($1) }
                    .map { level in
                        let wire = values[level]?.stringValue
                            ?? (values[level] == .null ? "" : level)
                        return ReasoningLevelDraft(level: level, wireValue: wire)
                    }
            } else {
                self.reasoningEnabled = false
                self.reasoningLevels = []
            }
        } else {
            self.reasoningEnabled = false
            self.reasoningLevels = []
        }
        self.baseJSON = json
    }

    static func reasoningSortIndex(_ level: String) -> Int {
        standardReasoningLevels.firstIndex(of: level) ?? standardReasoningLevels.count
    }

    func validationError(layout: ProviderLayout, existingIDs: Set<String>) -> String? {
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty { return "Every model needs an identifier." }
        if trimmedID != modelID { return "Model identifiers cannot start or end with whitespace." }
        if existingIDs.contains(trimmedID) { return "Model “\(trimmedID)” is listed more than once." }
        if let error = Self.integerError(contextWindow, label: "context window") { return error }
        if let error = Self.integerError(maxTokens, label: "maximum output tokens") { return error }
        if !includesText && !includesImage { return "Model “\(trimmedID)” must accept text or image input." }

        if layout == .piAI, reasoningEnabled {
            let active = reasoningLevels.filter { $0.level != "off" }
            if active.isEmpty {
                return "Model “\(trimmedID)” must offer a reasoning level beyond Off, or turn reasoning off."
            }
            var levels = Set<String>()
            for entry in reasoningLevels {
                if entry.level.isEmpty { return "Every reasoning row needs a level." }
                if !levels.insert(entry.level).inserted {
                    return "Reasoning level “\(entry.level)” is listed more than once."
                }
                if entry.level != "off", entry.wireValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "Reasoning level “\(entry.level)” needs the value sent to the API."
                }
            }
        }
        return nil
    }

    private static func integerError(_ value: String, label: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let number = Int(trimmed), number > 0 else {
            return "The \(label) must be a positive whole number."
        }
        return nil
    }

    func json(layout: ProviderLayout) -> JSONValue {
        var object = baseJSON?.objectValue ?? [:]
        object["id"] = .string(modelID.trimmingCharacters(in: .whitespacesAndNewlines))

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { object.removeValue(forKey: "name") } else { object["name"] = .string(trimmedName) }

        let context = contextWindow.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.isEmpty { object.removeValue(forKey: "contextWindow") } else if let number = Int(context) {
            object["contextWindow"] = .number(Double(number))
        }
        let maximum = maxTokens.trimmingCharacters(in: .whitespacesAndNewlines)
        if maximum.isEmpty { object.removeValue(forKey: "maxTokens") } else if let number = Int(maximum) {
            object["maxTokens"] = .number(Double(number))
        }

        var modalities: [JSONValue] = []
        if includesText { modalities.append(.string("text")) }
        if includesImage { modalities.append(.string("image")) }
        object[layout == .deepSeek ? "inputModalities" : "input"] = .array(modalities)
        if layout == .deepSeek {
            object.removeValue(forKey: "input")
        } else {
            object.removeValue(forKey: "inputModalities")
            if reasoningEnabled {
                var efforts: [String: JSONValue] = [:]
                for entry in reasoningLevels {
                    efforts[entry.level] = entry.level == "off" ? .null : .string(entry.wireValue)
                }
                object["reasoningEfforts"] = .object(efforts)
            } else if baseJSON?.objectValue?["reasoningEfforts"] != nil {
                // Only write an explicit false when this draft started from a
                // model that carried a reasoning declaration. Omitting the
                // field otherwise preserves the installed catalog capability.
                object["reasoningEfforts"] = .bool(false)
            }
        }
        return .object(object)
    }
}

struct ProviderDraft: Sendable {
    var providerID: String
    var displayName: String
    var baseURL: String
    var apiKeyEnv: String
    var api: ProviderProtocol?
    var layout: ProviderLayout
    var isNew: Bool
    var isCustom: Bool
    var modelsEdited: Bool
    var models: [ModelDraft]
    var effectiveModelCount: Int
    var defaultBaseURL: String?
    var baseURLEnv: [String]
    var nativeAuthEnv: [String]

    func credentialRef() -> String {
        let explicit = apiKeyEnv.trimmingCharacters(in: .whitespacesAndNewlines)
        return explicit.isEmpty ? ProviderRow.derivedCredentialRef(for: providerID) : explicit
    }

    func validationError(existingProviderIDs: Set<String>) -> String? {
        let trimmedID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty { return "Provider ID is required." }
        if isNew {
            guard trimmedID.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil else {
                return "Start with a lowercase letter; then use lowercase letters, digits, and dashes."
            }
            if existingProviderIDs.contains(trimmedID) {
                return "A provider already uses this ID."
            }
        }
        if api == nil && isCustom {
            return "Choose an API protocol."
        }
        let urlText = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCustom {
            guard !urlText.isEmpty else { return "Base URL is required." }
            guard let url = URL(string: urlText),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return "Enter a valid HTTP or HTTPS base URL."
            }
        } else if !urlText.isEmpty {
            guard let url = URL(string: urlText),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return "Enter a valid HTTP or HTTPS base URL."
            }
        }
        if isCustom && models.isEmpty { return "A custom provider needs at least one model." }

        var modelIDs = Set<String>()
        for model in models {
            if let error = model.validationError(layout: layout, existingIDs: modelIDs) {
                return error
            }
            modelIDs.insert(model.modelID)
        }
        return nil
    }

    func modelJSON() -> [JSONValue] {
        models.map { $0.json(layout: layout) }
    }

    /// Fields that are explicitly managed by the editor. Empty optional values
    /// are removed from the user section so the installed defaults apply again.
    func managedFields() -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { fields["displayName"] = .string(trimmedName) }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty { fields["baseURL"] = .string(trimmedURL) }
        if let api { fields["api"] = .string(api.rawValue) }
        if modelsEdited {
            fields["models"] = .array(modelJSON())
        }
        return fields
    }
}

// MARK: - Settings mutation

struct SettingsOperation: Encodable, Sendable {
    let op: String
    let path: [String]
    let value: JSONValue?

    static func set(_ path: [String], _ value: JSONValue) -> SettingsOperation {
        SettingsOperation(op: "set", path: path, value: value)
    }

    static func unset(_ path: [String]) -> SettingsOperation {
        SettingsOperation(op: "unset", path: path, value: nil)
    }
}

struct DiscoveredModel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let contextWindow: Int?
    let maxTokens: Int?
    let inputModalities: [String]?

    var displayName: String { name ?? id }

    var draft: ModelDraft {
        ModelDraft(
            modelID: id,
            name: name ?? "",
            contextWindow: contextWindow.map(String.init) ?? "",
            maxTokens: maxTokens.map(String.init) ?? "",
            includesText: inputModalities?.contains("text") ?? true,
            includesImage: inputModalities?.contains("image") ?? false,
            reasoningEnabled: false,
            reasoningLevels: []
        )
    }
}


// MARK: - OpenCode Go compatibility discovery

struct OpenCodeGoCatalog: Codable, Sendable {
    struct SkippedModel: Codable, Hashable, Sendable {
        let id: String
        let reason: String
    }

    let source: String
    let fetchedAt: String
    let models: [OpenCodeGoModel]
    let skipped: [SkippedModel]?
}

struct OpenCodeGoModel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let protocols: [String]
    let baseURLs: [String]
    let contextWindow: Int?
    let maxTokens: Int?
    let inputModalities: [String]
    let reasoningEfforts: [String]
    let skipped: [String]?

    var protocolLabels: [String] {
        protocols.map(Self.label(for:))
    }

    var hasUnmappedProtocol: Bool {
        protocols.isEmpty || skipped?.isEmpty == false
    }

    static func label(for protocolName: String) -> String {
        switch protocolName {
        case "openai-completions": return "OpenAI Chat Completions"
        case "openai-responses": return "OpenAI Responses"
        case "anthropic-messages": return "Anthropic Messages"
        case "google-generative-ai": return "Google Generative AI"
        default: return protocolName
        }
    }
}
