//
//  RenameSheet.swift
//  DeepSwift
//

import SwiftUI

enum RenameTarget: Identifiable {
    case session(SessionSummary)
    case workspace(WorkspaceItem)

    var id: String {
        switch self {
        case let .session(session): return "session-\(session.sessionId)"
        case let .workspace(workspace): return "workspace-\(workspace.workspaceId)"
        }
    }

    var currentTitle: String {
        switch self {
        case let .session(session): return session.title ?? session.displayTitle
        case let .workspace(workspace): return workspace.title
        }
    }
}

struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: RenameTarget
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(targetTitle)
                .font(.headline)
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { rename() }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") { rename() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { title = target.currentTitle }
    }

    private var targetTitle: String {
        switch target {
        case .session: return "Rename Session"
        case .workspace: return "Rename Workspace"
        }
    }

    private func rename() {
        let value = title
        switch target {
        case let .session(session):
            Task { await model.renameSession(session, to: value) }
        case let .workspace(workspace):
            Task { await model.renameWorkspace(workspace, to: value) }
        }
        dismiss()
    }
}
