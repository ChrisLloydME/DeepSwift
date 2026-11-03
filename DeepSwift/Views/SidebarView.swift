//
//  SidebarView.swift
//  DeepSwift
//

import AppKit
import SwiftUI

private enum SidebarSelection: Hashable {
    case workspace(String)
    case session(String)
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var renameTarget: RenameTarget?
    @State private var workspaceToDelete: WorkspaceItem?
    @State private var showArchived = false

    var body: some View {
        @Bindable var model = model
        List(selection: selectionBinding) {
            Section("Workspaces") {
                ForEach(model.workspaces) { workspace in
                    WorkspaceRow(workspace: workspace, isSelected: model.selectedWorkspaceID == workspace.workspaceId)
                        .tag(SidebarSelection.workspace(workspace.workspaceId))
                        .contextMenu {
                            Button("New Session Here") {
                                model.selectWorkspace(workspace.workspaceId)
                                Task { await model.createSession() }
                            }
                            Button("Rename…") {
                                renameTarget = .workspace(workspace)
                            }
                            Divider()
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace.path)])
                            }
                            Button("Copy Path") {
                                copy(workspace.path)
                            }
                            Divider()
                            Button("Remove Workspace…", role: .destructive) {
                                workspaceToDelete = workspace
                            }
                        }
                }
            }

            if let workspace = model.selectedWorkspace {
                Section(workspace.displayTitle) {
                    sessionRows(model.sessions(in: workspace))
                }
            } else if !model.visibleSessions.isEmpty {
                Section("Sessions") {
                    sessionRows(model.visibleSessions)
                }
            }

            if !model.ungroupedSessions.isEmpty {
                Section("Other Sessions") {
                    sessionRows(model.ungroupedSessions)
                }
            }

            if !archivedSessions.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archivedSessions) { session in
                            SessionRow(session: session)
                                .contextMenu {
                                    Button("Unarchive") {
                                        Task { await model.unarchiveSession(session.sessionId) }
                                    }
                                }
                        }
                    } label: {
                        Label("Archived Sessions", systemImage: "archivebox")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search Sessions")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RuntimeStatusBar()
        }
        .sheet(item: $renameTarget) { target in
            RenameSheet(target: target)
                .environment(model)
        }
        .confirmationDialog(
            "Remove this workspace from DeepSwift?",
            isPresented: Binding(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            ),
            presenting: workspaceToDelete
        ) { workspace in
            Button("Remove Workspace", role: .destructive) {
                Task { await model.deleteWorkspace(workspace) }
                workspaceToDelete = nil
            }
            Button("Cancel", role: .cancel) { workspaceToDelete = nil }
        } message: { workspace in
            Text("This removes the registration only. Files and sessions are retained by DSH.")
        }
    }

    @ViewBuilder
    private func sessionRows(_ sessions: [SessionSummary]) -> some View {
        ForEach(sessions) { session in
            SessionRow(session: session)
                .tag(SidebarSelection.session(session.sessionId))
                .contextMenu {
                    Button("Rename…") {
                        renameTarget = .session(session)
                    }
                    if model.pinnedSessionIDs.contains(session.sessionId) {
                        Button("Unpin") {
                            Task { await model.unpinSession(session) }
                        }
                    } else {
                        Button("Pin") {
                            Task { await model.pinSession(session) }
                        }
                    }
                    Button("Archive") {
                        Task { await model.archiveSession(session) }
                    }
                    if let cwd = session.cwd {
                        Divider()
                        Button("Reveal Workspace in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
                        }
                        Button("Copy Working Directory") {
                            copy(cwd)
                        }
                    }
                    Divider()
                    Button("Copy Session ID") {
                        copy(session.sessionId)
                    }
                }
        }
    }

    private var archivedSessions: [SessionSummary] {
        let ids = Set(model.archivedSessionIDs)
        return model.sessions.filter { ids.contains($0.sessionId) }
    }

    private var selectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: {
                if let id = model.selectedSessionID { return .session(id) }
                if let id = model.selectedWorkspaceID { return .workspace(id) }
                return nil
            },
            set: { selection in
                switch selection {
                case let .workspace(id):
                    model.selectSession(nil)
                    model.selectWorkspace(id)
                case let .session(id):
                    if let workspace = model.workspace(for: model.sessions.first(where: { $0.sessionId == id })) {
                        model.selectWorkspace(workspace.workspaceId)
                    }
                    model.selectSession(id)
                case nil:
                    break
                }
            }
        )
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct WorkspaceRow: View {
    let workspace: WorkspaceItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.displayTitle)
                    .lineLimit(1)
                Text("\(workspace.sessionIds.count) session\(workspace.sessionIds.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .help(workspace.abbreviatedPath)
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(session.isRunning ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let date = session.updatedDate {
                        Text(date, format: .relative(presentation: .named))
                    }
                    if session.agentAvailable == true {
                        Text("•")
                        Text("Ready")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .help(session.cwd ?? session.sessionId)
    }
}

private struct RuntimeStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.caption)
                    .lineLimit(1)
                if let version = model.runtimeFacts?.dshVersion ?? model.runtimeConfiguration?.dshVersion {
                    Text("DSH \(version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusColor: Color {
        switch model.connectionState {
        case .ready: return .green
        case .starting: return .orange
        case .degraded: return .orange
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    private var statusTitle: String {
        switch model.connectionState {
        case .ready: return "Runtime ready"
        case .starting: return "Starting…"
        case let .degraded(message): return message
        case let .failed(message): return message
        case .idle: return "Not connected"
        }
    }
}
