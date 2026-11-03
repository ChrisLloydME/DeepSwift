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
            ComposerView()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.conversation.hasMore {
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

            if let models = model.models, !models.isEmpty {
                ModelMenu(catalog: models)
            }

            Button {
                model.showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.borderless)
            .help("Toggle Inspector")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ModelMenu: View {
    @Environment(AppModel.self) private var model
    let catalog: ModelCatalog

    var body: some View {
        Menu {
            if catalog.groups.allSatisfy({ $0.models.isEmpty }) {
                Text("No models available for this profile")
            }
            ForEach(catalog.groups) { group in
                Section(group.name ?? group.id) {
                    ForEach(group.models) { model in
                        Button(model.displayName) {
                            Task {
                                await self.model.selectModel(ModelSelection(
                                    provider: group.id,
                                    model: model.id,
                                    reasoningEffort: model.reasoning?.defaultEffort
                                ))
                            }
                        }
                    }
                }
            }
            if let failures = catalog.failures, !failures.isEmpty {
                Divider()
                Section("Unavailable") {
                    ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                        Text("\(failure.provider ?? "Provider"): \(failure.message ?? "unavailable")")
                    }
                }
            }
        } label: {
            Label("Model", systemImage: "cpu")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Select model for this session")
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
                MarkdownTextView(text: live.text)
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
