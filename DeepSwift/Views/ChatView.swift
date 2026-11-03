//
//  ChatView.swift
//  DeepSwift
//

import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showTimestamps") private var showTimestamps = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ChatHeader()
            Divider()
            conversation
            if !model.pendingPrompts.isEmpty || model.conversation.live != nil {
                liveActivity
            }
            Divider()
            if model.selectedSession?.isSubagent == true {
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                    Text("Subagent conversation · read-only")
                        .font(.callout)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.bar)
            } else {
                ComposerView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.conversation.hasMore && model.conversation.firstSeq != nil {
                        HStack {
                            Spacer()
                            Button {
                                Task { await model.loadOlderMessages() }
                            } label: {
                                if model.isLoadingOlder {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Load Earlier Messages", systemImage: "arrow.up.circle")
                                }
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }

                    ForEach(model.conversation.items) { item in
                        MessageRow(item: item, showTimestamp: showTimestamps)
                            .id(item.id)
                    }

                    if let summary = model.changesSummary {
                        WorkspaceChangesCard(summary: summary) {
                            model.showChanges = true
                        }
                        .id("changes-\(summary.turn)")
                    }

                    ForEach(model.pendingPrompts) { prompt in
                        PendingUserMessage(prompt: prompt)
                            .id("pending-\(prompt.id)")
                    }

                    if model.isLoadingConversation && model.conversation.items.isEmpty {
                        LoadingConversationView()
                    }

                    if let live = model.conversation.live, live.hasVisibleContent {
                        LiveAssistantView(live: live)
                            .id("live-\(live.attemptId)")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.conversation.items.count) {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: model.conversation.live?.attemptId) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var liveActivity: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(model.conversation.live?.toolNames.last.map { "Running \($0)…" } ?? "DeepSeek is working…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stop") {
                Task { await model.cancelCurrentTurn() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
    }
}

private struct ChatHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedSession?.displayTitle ?? "Session")
                    .font(.headline)
                    .lineLimit(1)
                if let path = model.selectedSession?.cwd ?? model.conversation.header?.cwd {
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .help(path)
                }
            }
            Spacer()

            if model.selectedSession?.isRunning == true {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }

            PermissionPresetMenu()

            if let models = model.models, !models.isEmpty {
                if let selection = model.conversation.modelSelection, !models.contains(selection) {
                    Label("Selected model unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Choose another model from the Model menu.")
                }
                ModelMenu(catalog: models, selected: model.conversation.modelSelection)
            } else {
                SettingsLink {
                    Label("Configure Models", systemImage: "cpu")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Open Models settings")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ModelMenu: View {
    @Environment(AppModel.self) private var model
    let catalog: ModelCatalog
    let selected: ModelSelection?
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Label(selectedModelName ?? "Model", systemImage: "cpu")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Choose a model for this session")
        .sheet(isPresented: $showPicker) {
            ModelPickerSheet(catalog: catalog, selected: selected) { selection in
                Task { await self.model.selectModel(selection) }
            }
        }
    }

    private var selectedModelName: String? {
        guard let selected else { return nil }
        return catalog.model(for: selected)?.displayName
    }
}

private struct ModelRoute: Identifiable {
    let provider: String
    let providerName: String
    let model: ModelCatalog.Group.Model

    var id: String { "\(provider)/\(model.id)" }
}

private struct ModelPickerSheet: View {
    let catalog: ModelCatalog
    let selected: ModelSelection?
    let onSelect: (ModelSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    @State private var effort = ""

    init(catalog: ModelCatalog, selected: ModelSelection?, onSelect: @escaping (ModelSelection) -> Void) {
        self.catalog = catalog
        self.selected = selected
        self.onSelect = onSelect
        _selection = State(initialValue: selected.map { "\($0.provider)/\($0.model)" })
        _effort = State(initialValue: selected?.reasoningEffort ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose Model")
                        .font(.title3.weight(.semibold))
                    Text("Models are grouped by their DSH provider route.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()

            TextField("Search models or providers", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if allRoutes.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No Models Available", systemImage: "cpu")
                } description: {
                    Text("Configure a provider or sign in to DeepSeek Account in Models settings.")
                }
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(filteredGroups) { group in
                        Section(group.name ?? group.id) {
                            ForEach(group.models) { entry in
                                let routeID = "\(group.id)/\(entry.id)"
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName)
                                            .lineLimit(1)
                                        Text(group.name ?? group.id)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    if let efforts = entry.reasoning?.efforts, !efforts.isEmpty {
                                        Text("\(efforts.count) reasoning levels")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if routeID == selection {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                            .accessibilityLabel("Selected model")
                                    }
                                }
                                .contentShape(Rectangle())
                                .tag(routeID)
                            }
                        }
                    }
                    if let failures = catalog.failures, !failures.isEmpty {
                        Section("Unavailable Providers") {
                            ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                                Text("\(failure.displayName): \(failure.message ?? "unavailable")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack(alignment: .center, spacing: 12) {
                if let route = selectedRoute {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.model.displayName)
                            .font(.callout.weight(.medium))
                        Text(route.providerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let efforts = route.model.reasoning?.efforts, !efforts.isEmpty {
                        Picker("Reasoning", selection: $effort) {
                            Text("Default").tag("")
                            ForEach(efforts, id: \.id) { level in
                                Text(level.displayName).tag(level.id)
                            }
                            if !effort.isEmpty && !efforts.contains(where: { $0.id == effort }) {
                                Text(effort).tag(effort)
                            }
                        }
                        .fixedSize()
                    }
                } else {
                    Text("Select a model to continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use Model") {
                    guard let route = selectedRoute else { return }
                    let reasoning = route.model.reasoning?.efforts?.isEmpty == false && !effort.isEmpty
                        ? effort
                        : route.model.reasoning?.defaultEffort
                    onSelect(ModelSelection(
                        provider: route.provider,
                        model: route.model.id,
                        reasoningEffort: reasoning
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRoute == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 680, height: 560)
        .onChange(of: selection) {
            updateEffortForSelection()
        }
    }

    private var allRoutes: [ModelRoute] {
        catalog.groups.flatMap { group in
            group.models.map { ModelRoute(provider: group.id, providerName: group.name ?? group.id, model: $0) }
        }
    }

    private var filteredGroups: [ModelCatalog.Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return catalog.groups }
        return catalog.groups.compactMap { group in
            let models = group.models.filter { entry in
                entry.id.localizedCaseInsensitiveContains(needle)
                    || entry.displayName.localizedCaseInsensitiveContains(needle)
                    || (group.name ?? group.id).localizedCaseInsensitiveContains(needle)
            }
            guard !models.isEmpty else { return nil }
            return ModelCatalog.Group(id: group.id, name: group.name, models: models)
        }
    }

    private var selectedRoute: ModelRoute? {
        allRoutes.first { $0.id == selection }
    }

    private func updateEffortForSelection() {
        guard let route = selectedRoute else {
            effort = ""
            return
        }
        if let selected,
           selected.provider == route.provider,
           selected.model == route.model.id {
            effort = selected.reasoningEffort ?? ""
        } else {
            effort = ""
        }
    }
}

private struct PendingUserMessage: View {
    let prompt: AppModel.PendingPrompt

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 4) {
                if !prompt.text.isEmpty {
                    Text(prompt.text)
                        .textSelection(.enabled)
                }
                if !prompt.attachmentNames.isEmpty {
                    Label("\(prompt.attachmentNames.count) image\(prompt.attachmentNames.count == 1 ? "" : "s")", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(5)
                }
        }
    }
}

private struct LoadingConversationView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading conversation…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

private struct LiveAssistantView: View {
    let live: LiveAssistant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !live.reasoning.isEmpty {
                DisclosureGroup {
                    Text(live.reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Thinking", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !live.text.isEmpty {
                // Plain text keeps token-by-token streaming cheap; the
                // committed assistant message renders through the full
                // Markdown block renderer.
                Text(live.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !live.toolNames.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("Preparing \(live.toolNames.joined(separator: ", "))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Model Picker — Large Catalog") {
    let groups = (0..<4).map { groupIndex in
        ModelCatalog.Group(
            id: "provider-\(groupIndex)",
            name: "Provider \(groupIndex + 1)",
            models: (0..<20).map { modelIndex in
                ModelCatalog.Group.Model(
                    id: "model-\(groupIndex)-\(modelIndex)",
                    name: "Model \(groupIndex + 1).\(modelIndex + 1) with a representative display name",
                    reasoning: modelIndex.isMultiple(of: 3)
                        ? .init(defaultEffort: "medium", efforts: [
                            .init(id: "low", name: "Low", description: nil),
                            .init(id: "medium", name: "Medium", description: nil),
                            .init(id: "high", name: "High", description: nil)
                        ])
                        : nil,
                    available: true
                )
            }
        )
    }
    ModelPickerSheet(
        catalog: ModelCatalog(defaultSelection: nil, groups: groups, failures: nil),
        selected: nil,
        onSelect: { _ in }
    )
}
#endif
