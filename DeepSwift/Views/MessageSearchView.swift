//
//  MessageSearchView.swift
//  DeepSwift
//

import SwiftUI

struct MessageSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search messages", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await model.searchMessages() } }
                if model.isSearchingMessages {
                    ProgressView().controlSize(.small)
                }
                Button("Search") {
                    model.searchQuery = query
                    Task { await model.searchMessages() }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            Divider()

            if model.searchResults.isEmpty {
                ContentUnavailableView(
                    "Search Conversations",
                    systemImage: "text.magnifyingglass",
                    description: Text("Search the durable message content of sessions in this DSH profile.")
                )
            } else {
                List(model.searchResults) { hit in
                    Button {
                        if let session = model.sessions.first(where: { $0.sessionId == hit.sessionId }) {
                            if let workspace = model.workspace(for: session) {
                                model.selectWorkspace(workspace.workspaceId)
                            }
                            model.selectSession(session.sessionId)
                        }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.sessions.first(where: { $0.sessionId == hit.sessionId })?.displayTitle ?? hit.sessionId)
                                .font(.headline)
                                .lineLimit(1)
                            Text(hit.snippet)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { query = model.searchQuery }
    }
}
