//
//  ProviderSettingsView.swift
//  DeepSwift
//

import AppKit
import SwiftUI

struct ProviderEditorSeed: Identifiable {
    enum Mode: Equatable {
        case edit
        case newBuiltIn
        case newCustom
    }

    let id = UUID()
    let mode: Mode
    let draft: ProviderDraft
}

// MARK: - Models settings section

struct ProviderSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var editorSeed: ProviderEditorSeed?
    @State private var pendingRemoval: ProviderRow?
    @State private var actionError: String?

    var body: some View {
        Section("Model Providers") {
            if model.isLoadingProviders && model.providerRows.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading provider directory…")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(model.providerRows) { row in
                ProviderRowView(row: row) {
                    editorSeed = ProviderEditorSeed(mode: .edit, draft: model.providerDraft(for: row))
                } onRemove: {
                    pendingRemoval = row
                }
                .disabled(!model.providerSettingsWritable)
            }

            if model.providerRows.isEmpty && !model.isLoadingProviders {
                Text("No API-key providers are configured. DeepSeek Account is configured separately above.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Menu {
                    Button("Built-in Provider…") {
                        guard let provider = model.unconfiguredProviders.first else { return }
                        editorSeed = ProviderEditorSeed(
                            mode: .newBuiltIn,
                            draft: model.newBuiltInProviderDraft(for: provider)
                        )
                    }
                    .disabled(model.unconfiguredProviders.isEmpty)

                    Button("Custom Provider…") {
                        editorSeed = ProviderEditorSeed(mode: .newCustom, draft: model.newCustomProviderDraft())
                    }
                } label: {
                    Label("Add Model Provider", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!model.providerSettingsWritable)

                Button {
                    Task { await model.refreshProviderSettings() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingProviders)
            }

            if !model.providerSettingsWritable {
                Text("This profile does not accept provider writes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = actionError ?? model.providerError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .sheet(item: $editorSeed) { seed in
            ProviderEditorSheet(seed: seed)
                .environment(model)
        }
        .alert("Remove Model Provider?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button("Remove", role: .destructive) {
                guard let row = pendingRemoval else { return }
                pendingRemoval = nil
                Task {
                    do {
                        try await model.removeProvider(row)
                        actionError = nil
                    } catch {
                        actionError = AppErrorPresentationFactory.summary(error.localizedDescription)
                            ?? "The provider could not be removed."
                    }
                }
            }
        } message: {
            if let row = pendingRemoval {
                Text("Remove \(row.displayName) from this isolated DSH profile? Its managed API key is removed too when DeepSwift owns the derived credential reference.")
            }
        }
    }
}

private struct ProviderRowView: View {
    let row: ProviderRow
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.layout == .deepSeek ? "bolt.horizontal" : "server.rack")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.headline)
                    if row.isCustom {
                        Text("Custom")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(row.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 5) {
                    Circle()
                        .fill(authColor)
                        .frame(width: 6, height: 6)
                    Text(authSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = row.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(row.modelCount == 1 ? "1 model" : "\(row.modelCount) models")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button("Edit", action: onEdit)
                        .buttonStyle(.borderless)
                    if row.layout == .piAI {
                        Menu {
                            Button("Remove…", role: .destructive, action: onRemove)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Provider actions")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var authSummary: String {
        if let credential = row.credential {
            if credential.configured {
                return "API key configured · \(credential.sourceLabel)"
            }
            return "API key not configured"
        }
        if !row.nativeAuthEnv.isEmpty {
            return "Native authentication: \(row.nativeAuthEnv.prefix(2).joined(separator: ", "))"
        }
        return "API key not configured"
    }

    private var authColor: Color {
        if row.credential?.configured == true { return .green }
        if !row.nativeAuthEnv.isEmpty { return .secondary }
        return .orange
    }
}

// MARK: - Provider editor

private struct ProviderEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let seed: ProviderEditorSeed
    @State private var draft: ProviderDraft
    @State private var apiKey = ""
    @State private var revealKey = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showDiscovery = false
    @State private var showOpenCodeCatalog = false
    @State private var showRestoreOpenCode = false
    @State private var pendingCredentialRemoval: String?

    init(seed: ProviderEditorSeed) {
        self.seed = seed
        _draft = State(initialValue: seed.draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
            .padding(20)
            if let errorText {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorText)
                        .textSelection(.enabled)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            Divider()

            Form {
                providerSection
                authenticationSection
                modelsSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 740, height: 700)
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $showOpenCodeCatalog) {
            OpenCodeGoCatalogSheet()
                .environment(model)
        }
        .confirmationDialog(
            "Restore the installed OpenCode Go catalog?",
            isPresented: $showRestoreOpenCode
        ) {
            Button("Restore Installed Catalog", role: .destructive) {
                Task {
                    do {
                        try await model.restoreOpenCodeGoCatalog()
                        dismiss()
                    } catch {
                        errorText = AppErrorPresentationFactory.summary(error.localizedDescription)
                            ?? "The provider settings request did not complete."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes route-level API, base URL, model, and model-override entries for OpenCode Go so its per-model protocols and sessions come from the pinned DSH catalog again. The API key reference is preserved.")
        }
        .sheet(isPresented: $showDiscovery) {
            ModelDiscoverySheet(
                settingsNamespace: draft.layout == .deepSeek ? "llm-deepseek" : "llm-pi-ai",
                provider: draft.providerID.isEmpty ? nil : draft.providerID,
                baseURL: draft.baseURL,
                api: draft.api?.rawValue,
                apiKey: apiKey,
                existingIDs: Set(draft.models.map(\.modelID))
            ) { candidates in
                merge(candidates)
            }
            .environment(model)
        }
        .confirmationDialog(
            "Remove saved API key?",
            isPresented: Binding(
                get: { pendingCredentialRemoval != nil },
                set: { if !$0 { pendingCredentialRemoval = nil } }
            )
        ) {
            Button("Remove API Key", role: .destructive) {
                guard let reference = pendingCredentialRemoval else { return }
                pendingCredentialRemoval = nil
                Task {
                    do {
                        try await model.removeCredential(reference: reference)
                        errorText = nil
                    } catch {
                        errorText = AppErrorPresentationFactory.summary(error.localizedDescription)
                            ?? "The provider settings request did not complete."
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingCredentialRemoval = nil }
        } message: {
            Text("The provider reference remains in place, so environment or native authentication can apply again.")
        }
    }

    private var isOpenCodeGo: Bool {
        draft.providerID == "opencode-go" && !draft.isCustom
    }

    private var hasOpenCodeRouteOverrides: Bool {
        !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.api != nil
            || draft.modelsEdited
    }

    private var title: String {
        switch seed.mode {
        case .edit: "Edit \(draft.displayName)"
        case .newBuiltIn, .newCustom: "Add Model Provider"
        }
    }

    private var subtitle: String {
        switch seed.mode {
        case .edit:
            "Provider ID, endpoint, credentials, and model catalog."
        case .newBuiltIn:
            "Activate a provider supplied by the installed DSH catalog."
        case .newCustom:
            "Declare an OpenAI- or Anthropic-compatible endpoint."
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        Section("Provider") {
            if seed.mode == .newBuiltIn {
                Picker("Provider", selection: Binding(
                    get: { draft.providerID },
                    set: { providerID in
                        guard let entry = model.unconfiguredProviders.first(where: { $0.provider == providerID }) else { return }
                        draft = model.newBuiltInProviderDraft(for: entry)
                        apiKey = ""
                        revealKey = false
                    }
                )) {
                    ForEach(model.unconfiguredProviders) { entry in
                        Text(entry.displayName).tag(entry.provider)
                    }
                }
            } else if draft.isNew {
                TextField("Provider ID", text: $draft.providerID)
                    .font(.body.monospaced())
                    .accessibilityIdentifier("providerIDField")
                Text("Start with a lowercase letter; then use lowercase letters, digits, and dashes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Provider ID") {
                    Text(draft.providerID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            TextField("Display Name", text: $draft.displayName, prompt: Text(draft.providerID.isEmpty ? "Provider name" : draft.providerID))
                .accessibilityIdentifier("providerDisplayNameField")

            if isOpenCodeGo {
                LabeledContent("API Protocol", value: "Per model · installed catalog")
                LabeledContent("Base URL", value: "Per model · installed catalog")
            } else {
                if draft.isCustom {
                    Picker("API Protocol", selection: Binding(
                        get: { draft.api ?? .openAICompletions },
                        set: { draft.api = $0 }
                    )) {
                        ForEach(ProviderProtocol.allCases) { api in
                            Text(api.displayName).tag(api)
                        }
                    }
                } else if let api = draft.api {
                    LabeledContent("API Protocol", value: api.displayName)
                } else {
                    LabeledContent("API Protocol", value: "Installed catalog")
                }

                TextField(
                    "Base URL",
                    text: $draft.baseURL,
                    prompt: Text(draft.defaultBaseURL ?? draft.api?.endpointPlaceholder ?? "Provider default")
                )
                .accessibilityIdentifier("providerBaseURLField")
            }
            if !draft.baseURLEnv.isEmpty {
                Text("Environment endpoint variables: \(draft.baseURLEnv.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var authenticationSection: some View {
        let reference = draft.credentialRef()
        let status = model.providerCredentials[reference]

        Section("Authentication") {
            LabeledContent("Credential Reference") {
                Text(reference)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            LabeledContent("Status") {
                Text(status?.sourceLabel ?? "Not configured")
                    .foregroundStyle(status?.configured == true ? .green : .secondary)
            }

            HStack(spacing: 8) {
                Group {
                    if revealKey {
                        TextField("API Key", text: $apiKey, prompt: Text("Paste a new API key"))
                            .accessibilityIdentifier("providerAPIKeyField")
                    } else {
                        SecureField("API Key", text: $apiKey, prompt: Text("Paste a new API key"))
                            .accessibilityIdentifier("providerAPIKeyField")
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    revealKey.toggle()
                } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealKey ? "Hide API key" : "Show API key")
                .accessibilityLabel(revealKey ? "Hide API key" : "Show API key")
            }

            Text("Keys are written through the isolated DSH credentials service. Stored values are never read back into DeepSwift. Leave this field blank to keep the current credential.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if status?.configured == true, status?.isWritable == true {
                Button("Remove Saved API Key…") {
                    pendingCredentialRemoval = reference
                }
                .buttonStyle(.borderless)
            }

            DisclosureGroup("Advanced") {
                TextField(
                    "Credential reference",
                    text: $draft.apiKeyEnv,
                    prompt: Text(ProviderRow.derivedCredentialRef(for: draft.providerID))
                )
                .font(.caption.monospaced())
                Text("Leave blank to use \(ProviderRow.derivedCredentialRef(for: draft.providerID)). An environment reference can be used without storing a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !draft.nativeAuthEnv.isEmpty {
                Text("Environment/native authentication: \(draft.nativeAuthEnv.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        Section("Models") {
            if isOpenCodeGo {
                LabeledContent(
                    "Installed Catalog",
                    value: draft.effectiveModelCount == 1 ? "1 routed model" : "\(draft.effectiveModelCount) routed models"
                )
                Text("OpenCode Go routes different models through different protocols. The pinned DSH catalog supplies each model’s API, base URL, and per-conversation session header, so DeepSwift leaves route-level overrides unset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasOpenCodeRouteOverrides {
                    Label("This provider has route-level overrides or a model list. Those can collapse per-model routing.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 12) {
                    Button {
                        showOpenCodeCatalog = true
                    } label: {
                        Label("Inspect Live OpenCode Catalog…", systemImage: "cloud")
                    }
                    .buttonStyle(.borderless)

                    if hasOpenCodeRouteOverrides {
                        Button {
                            showRestoreOpenCode = true
                        } label: {
                            Label("Restore Installed Catalog…", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else if !draft.isCustom && !draft.modelsEdited {
                LabeledContent("Catalog", value: draft.effectiveModelCount == 1 ? "1 installed model" : "\(draft.effectiveModelCount) installed models")
                Text("Models are inherited from the installed provider catalog. Customize them only when this provider needs an override.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Customize Models…") {
                    if draft.models.isEmpty {
                        draft.models = [ModelDraft()]
                    }
                    draft.modelsEdited = true
                }
                .buttonStyle(.borderless)
            } else {
                if draft.models.isEmpty {
                    Text("No models configured yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach($draft.models) { $entry in
                    let entryID = entry.id
                    let index = draft.models.firstIndex(where: { $0.id == entryID }) ?? 0
                    ModelEditorRow(
                        model: $entry,
                        layout: draft.layout,
                        canMoveUp: index > 0,
                        canMoveDown: index < draft.models.count - 1,
                        onMoveUp: { move(entryID, by: -1) },
                        onMoveDown: { move(entryID, by: 1) },
                        onRemove: {
                            draft.models.removeAll { $0.id == entryID }
                        }
                    )
                }

                HStack(spacing: 12) {
                    Button {
                        draft.models.append(ModelDraft())
                        draft.modelsEdited = true
                    } label: {
                        Label("Add Model", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        showDiscovery = true
                    } label: {
                        Label("Discover Models…", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if draft.isCustom && draft.models.isEmpty {
                Text("A custom provider requires at least one model identifier.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = draft.models.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard draft.models.indices.contains(target) else { return }
        draft.models.swapAt(index, target)
    }

    private func merge(_ candidates: [DiscoveredModel]) {
        draft.modelsEdited = true
        for candidate in candidates where !draft.models.contains(where: { $0.modelID == candidate.id }) {
            draft.models.append(candidate.draft)
        }
    }

    private func save() {
        errorText = nil
        isSaving = true
        Task {
            do {
                try await model.saveProvider(draft, apiKey: apiKey)
                apiKey = ""
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorText = AppErrorPresentationFactory.summary(error.localizedDescription)
                ?? "The provider settings request did not complete."
            }
        }
    }
}

// MARK: - Model editor

private struct ModelEditorRow: View {
    @Binding var model: ModelDraft
    let layout: ProviderLayout
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    @State private var expanded: Bool

    init(
        model: Binding<ModelDraft>,
        layout: ProviderLayout,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        _model = model
        self.layout = layout
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onRemove = onRemove
        _expanded = State(initialValue: model.wrappedValue.modelID.isEmpty)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Model ID", text: $model.modelID)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("modelIDField")
                    TextField("Display Name", text: $model.name, prompt: Text("Optional"))

                    HStack(spacing: 10) {
                        TextField("Context window", text: $model.contextWindow, prompt: Text("Inherited"))
                        TextField("Max output tokens", text: $model.maxTokens, prompt: Text("Default"))
                    }
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: 16) {
                        Toggle("Text input", isOn: $model.includesText)
                        Toggle("Image input", isOn: $model.includesImage)
                    }
                    .toggleStyle(.checkbox)

                    if layout == .piAI {
                        Divider()
                        ReasoningEditor(
                            enabled: $model.reasoningEnabled,
                            levels: $model.reasoningLevels
                        )
                    }
                }
                .padding(.vertical, 4)
            } label: {
                HStack(spacing: 6) {
                    Text(model.modelID.isEmpty ? "New Model" : model.modelID)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(modalitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move model up")
                .accessibilityLabel("Move model up")

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move model down")
                .accessibilityLabel("Move model down")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove model")
                .accessibilityLabel("Remove model")
            }
        }
    }

    private var modalitySummary: String {
        switch (model.includesText, model.includesImage) {
        case (true, true): "Text + Image"
        case (true, false): "Text"
        case (false, true): "Image"
        case (false, false): "No input"
        }
    }
}

private struct ReasoningEditor: View {
    @Binding var enabled: Bool
    @Binding var levels: [ReasoningLevelDraft]

    var body: some View {
        Toggle("Supports reasoning", isOn: $enabled)
        if enabled {
            Text("Map each offered level to the value this API expects. Off may use an empty value.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($levels) { $level in
                HStack(spacing: 8) {
                    Picker("Level", selection: $level.level) {
                        ForEach(availableLevels(for: level.level), id: \.self) { name in
                            Text(name.capitalized).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)

                    TextField("API value", text: $level.wireValue)
                        .font(.caption.monospaced())
                        .disabled(level.level == "off")

                    Button {
                        levels.removeAll { $0.id == level.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove reasoning level")
                }
            }

            Button("Add Reasoning Level") {
                let used = Set(levels.map(\.level))
                let next = ModelDraft.standardReasoningLevels.first { !used.contains($0) } ?? "custom"
                levels.append(ReasoningLevelDraft(level: next, wireValue: next))
            }
            .buttonStyle(.borderless)
        }
    }

    private func availableLevels(for current: String) -> [String] {
        var values = ModelDraft.standardReasoningLevels
        if !values.contains(current) { values.append(current) }
        return values
    }
}

// MARK: - Discovery

private struct ModelDiscoverySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let settingsNamespace: String
    let provider: String?
    let baseURL: String
    let api: String?
    let apiKey: String
    let existingIDs: Set<String>
    let onAdd: ([DiscoveredModel]) -> Void

    @State private var results: [DiscoveredModel] = []
    @State private var selected = Set<String>()
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover Models")
                        .font(.title3.weight(.semibold))
                    Text(provider ?? "Custom endpoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()

            VStack(spacing: 10) {
                HStack {
                    TextField("Search models", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button("Select All") {
                        selected.formUnion(filteredResults.filter { !existingIDs.contains($0.id) }.map(\.id))
                    }
                    .buttonStyle(.borderless)
                    Button("Deselect All") {
                        selected.removeAll()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                if isLoading {
                    Spacer()
                    ProgressView("Querying model catalog…")
                    Spacer()
                } else if let errorText {
                    Spacer()
                    ContentUnavailableView {
                        Label("Discovery Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorText)
                    }
                    Spacer()
                } else if filteredResults.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label("No Models Found", systemImage: "magnifyingglass")
                    } description: {
                        Text("Enter a model identifier manually in the provider editor, or try a different endpoint.")
                    }
                    Spacer()
                } else {
                    List(filteredResults) { candidate in
                        HStack(spacing: 10) {
                            Toggle("", isOn: selectionBinding(for: candidate.id))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .disabled(existingIDs.contains(candidate.id))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.displayName)
                                    .lineLimit(1)
                                Text(candidate.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if existingIDs.contains(candidate.id) {
                                Text("Already configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let context = candidate.contextWindow {
                                Text("\(context.formatted()) ctx")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }

            Divider()
            HStack {
                Text(selected.count == 1 ? "1 model selected" : "\(selected.count) models selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Selected") {
                    let chosen = results.filter { selected.contains($0.id) }
                    onAdd(chosen)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(18)
        }
        .frame(width: 620, height: 540)
        .task { await load() }
    }

    private var filteredResults: [DiscoveredModel] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return results }
        return results.filter {
            $0.id.localizedCaseInsensitiveContains(needle)
                || $0.displayName.localizedCaseInsensitiveContains(needle)
        }
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isSelected in
                if isSelected { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        do {
            results = try await model.discoverModels(
                settingsNamespace: settingsNamespace,
                provider: provider,
                baseURL: baseURL,
                api: api,
                apiKey: apiKey
            )
            isLoading = false
        } catch {
            isLoading = false
            errorText = AppErrorPresentationFactory.summary(error.localizedDescription)
                ?? "The provider settings request did not complete."
        }
    }
}


// MARK: - OpenCode Go live catalog

private struct OpenCodeGoCatalogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var catalog: OpenCodeGoCatalog?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenCode Go — Live Model Catalog")
                        .font(.title3.weight(.semibold))
                    Text("Read-only metadata from \(OpenCodeGoCatalogSource.displayURL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await load() }
                }
                .disabled(isLoading)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Fetching OpenCode Go model metadata…")
                Spacer()
            } else if let errorText {
                Spacer()
                ContentUnavailableView {
                    Label("OpenCode Go Catalog Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
                Spacer()
            } else if let catalog, catalog.models.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No Chat Models Returned", systemImage: "tray")
                } description: {
                    Text("The endpoint answered successfully but returned no chat model metadata.")
                }
                Spacer()
            } else if let catalog {
                VStack(spacing: 10) {
                    HStack {
                        TextField("Search models or protocols", text: $query)
                            .textFieldStyle(.roundedBorder)
                        Text("\(catalog.models.count) live · \(installedCount) in pinned catalog")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    List(filtered(catalog.models)) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                    .font(.headline)
                                Text(entry.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(entry.protocolLabels.isEmpty ? "Unrecognized API" : entry.protocolLabels.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(entry.protocolLabels.isEmpty ? .orange : .secondary)
                                HStack(spacing: 12) {
                                    if let context = entry.contextWindow {
                                        Text("Context \(context.formatted())")
                                    }
                                    if let maximum = entry.maxTokens {
                                        Text("Max \(maximum.formatted())")
                                    }
                                    if !entry.inputModalities.isEmpty {
                                        Text(entry.inputModalities.joined(separator: " + "))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 8)
                            if !entry.reasoningEfforts.isEmpty {
                                Text("Reasoning · \(entry.reasoningEfforts.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !installedIDs.contains(entry.id) {
                                Label("Not in pinned catalog", systemImage: "exclamationmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .help("This live model has no installed DSH catalog descriptor, so the pinned runtime cannot route it.")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            }

            Divider()
            HStack {
                Text("OpenCode Go uses per-model protocols and a per-conversation x-opencode-session header through the pinned pi-ai adapter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(18)
        }
        .frame(width: 720, height: 560)
        .task { await load() }
    }

    private var installedIDs: Set<String> {
        let discovered = Set(model.installedProviderModels["opencode-go"]?.map(\.id) ?? [])
        if !discovered.isEmpty { return discovered }
        return Set(model.models?.groups.first(where: { $0.id == "opencode-go" })?.models.map(\.id) ?? [])
    }

    private var installedCount: Int {
        installedIDs.count
    }

    private func filtered(_ models: [OpenCodeGoModel]) -> [OpenCodeGoModel] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return models }
        return models.filter { entry in
            entry.id.localizedCaseInsensitiveContains(needle)
                || entry.name.localizedCaseInsensitiveContains(needle)
                || entry.protocolLabels.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            let result = try await model.discoverOpenCodeModels()
            catalog = result
            isLoading = false
        } catch {
            errorText = AppErrorPresentationFactory.summary(error.localizedDescription)
                ?? "The provider settings request did not complete."
            isLoading = false
        }
    }
}

private enum OpenCodeGoCatalogSource {
    static let displayURL = "https://opencode.ai/inference/go/v1/models"
}

#if DEBUG
#Preview("Provider Editor") {
    let model = PreviewData.model()
    model.providerSettingsWritable = true
    var draft = model.newCustomProviderDraft()
    draft.providerID = "example-gateway"
    draft.displayName = "Example Gateway"
    draft.baseURL = "https://gateway.example/v1"
    draft.models = [
        ModelDraft(
            modelID: "example-chat",
            name: "Example Chat",
            contextWindow: "128000",
            maxTokens: "8192",
            includesText: true,
            includesImage: false
        )
    ]
    return ProviderEditorSheet(seed: ProviderEditorSeed(mode: .newCustom, draft: draft))
        .environment(model)
}
#endif
