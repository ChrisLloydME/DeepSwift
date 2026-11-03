//
//  InspectorView.swift
//  DeepSwift
//

import AppKit
import SwiftUI

/// Trailing inspector for the selected session.
///
/// The view is presentation-only: it reads the same `AppModel` as the main
/// window, uses native `Form`/`Section`/`LabeledContent`, and never owns its
/// own toolbar state. Visibility is controlled by the window-level
/// `showInspector` binding.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let session = model.selectedSession {
                Form {
                    sessionSection(session)
                    subagentSection(session)
                    workspaceSection(session)
                    modelSection
                    jobsSection
                    activitySection
                    terminalSection
                    runtimeSection
                }
                .formStyle(.grouped)
                .controlSize(.regular)
            } else {
                ContentUnavailableView {
                    Label("No Session Selected", systemImage: "sidebar.trailing")
                } description: {
                    Text("Select a session to inspect its workspace, model, and runtime state.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
            }
        }
    }

    private func sessionSection(_ session: SessionSummary) -> some View {
        Section("Session") {
            LabeledContent("Title") {
                Text(session.displayTitle)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }

            LabeledContent("Status") {
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.isRunning ? Color.accentColor : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(session.isRunning ? "Running" : (session.agentAvailable == true ? "Ready" : "Idle"))
                }
            }

            if let date = session.updatedDate {
                LabeledContent("Updated") {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                }
            }

            LabeledContent("Preset") {
                Text(model.conversation.header?.agentPreset ?? "Default")
            }

            LabeledContent("Permission") {
                Text(model.conversation.permissionPreset ?? "Default")
            }

            LabeledContent("Identifier") {
                Text(session.sessionId)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(session.sessionId)
            }

            Button {
                copy(session.sessionId)
            } label: {
                Label("Copy Session ID", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func subagentSection(_ session: SessionSummary) -> some View {
        let children = model.subagents(of: session)
        if !children.isEmpty {
            Section("Subagents") {
                ForEach(children) { child in
                    Button {
                        model.selectSubagent(child)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(child.isRunning ? Color.accentColor : Color.secondary)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(child.displayTitle)
                                    .lineLimit(1)
                                if let updated = child.updatedDate {
                                    Text(updated, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workspaceSection(_ session: SessionSummary) -> some View {
        Section("Workspace") {
            if let workspace = model.workspace(for: session) ?? model.selectedWorkspace {
                LabeledContent("Name") {
                    Text(workspace.displayTitle)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Path") {
                    Text(workspace.abbreviatedPath)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(workspace.path)
                }

                HStack(spacing: 14) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace.path)])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    Button {
                        copy(workspace.path)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(.borderless)
            } else if let cwd = session.cwd {
                LabeledContent("Path") {
                    Text((cwd as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(cwd)
                }
            } else {
                Text("No workspace information")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        Section("Model") {
            if let models = model.models, !models.groups.isEmpty {
                ForEach(models.groups) { group in
                    ForEach(group.models) { entry in
                        Button {
                            Task {
                                await model.selectModel(ModelSelection(
                                    provider: group.id,
                                    model: entry.id,
                                    reasoningEffort: entry.reasoning?.defaultEffort
                                ))
                            }
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.displayName)
                                    Text(group.name ?? group.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if entry.id == models.defaultSelection?.model {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Default model")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("No routable models")
                    .foregroundStyle(.secondary)
                Text("Authenticate the isolated DSH profile before using model-backed sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var jobsSection: some View {
        if !model.jobs.isEmpty {
            Section("Background Jobs") {
                ForEach(model.jobs) { job in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(job.isActive ? Color.accentColor : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text(job.displayLabel)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if job.isActive {
                                Button("Stop") {
                                    Task { await model.killJob(job) }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                        if let progress = job.progress, !progress.isEmpty {
                            Text(progress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let detail = job.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        Section("Activity") {
            let items = model.conversation.items
            LabeledContent("Messages", value: "\(items.filter { $0.isUser }.count)")
            LabeledContent("Replies", value: "\(items.filter { $0.isAssistant }.count)")
            LabeledContent("Tool Calls", value: "\(items.filter { if case .tool = $0.kind { return true }; return false }.count)")
            LabeledContent("Stream", value: model.conversation.isLoaded ? "Loaded" : "Not loaded")
            if let first = model.conversation.firstSeq {
                LabeledContent("Oldest Seq", value: "\(first)")
            }
            if model.conversation.hasMore {
                LabeledContent("History", value: "More available")
            }
        }
    }

    private var terminalSection: some View {
        Section("Terminal") {
            Label("Terminal integration is not available in this build.", systemImage: "terminal")
                .foregroundStyle(.secondary)
            Text("DeepSwift does not start a separate shell outside the DSH runtime. The official terminal controller can be wired in a later phase.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runtimeSection: some View {
        Section("Runtime") {
            LabeledContent("State", value: model.connectionState.label)
            if let version = model.runtimeFacts?.dshVersion ?? model.runtimeConfiguration?.dshVersion {
                LabeledContent("DSH", value: version)
            }
            if let node = model.runtimeFacts?.nodeVersion {
                LabeledContent("Node", value: node)
            }
            if let home = model.runtimeConfiguration?.dshHome {
                LabeledContent("Profile") {
                    Text((home as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(home)
                }
            }
            Button {
                model.revealRuntimeLog()
            } label: {
                Label("Reveal Profile Folder", systemImage: "folder")
            }
            .buttonStyle(.borderless)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
