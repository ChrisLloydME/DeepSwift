//
//  SubagentComposer.swift
//  DeepSwift
//

import SwiftUI

/// Message composer for a live continuable subagent. Queue appends a turn;
/// Steer targets the nearest running step through the official subagent API.
struct SubagentComposer: View {
    @Environment(AppModel.self) private var model
    @Bindable var modelBinding: AppModel

    init(model: AppModel) {
        self.modelBinding = model
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .foregroundStyle(.secondary)
                Text("Subagent conversation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isSendingSubagent {
                    ProgressView().controlSize(.mini)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message subagent…", text: $modelBinding.subagentDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit {
                        Task { await model.sendSubagentMessage(delivery: "queue") }
                    }
                Button("Queue") {
                    Task { await model.sendSubagentMessage(delivery: "queue") }
                }
                .disabled(model.subagentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSendingSubagent)
                Button("Steer") {
                    Task { await model.sendSubagentMessage(delivery: "steer") }
                }
                .disabled(model.selectedSession?.isRunning != true || model.subagentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSendingSubagent)
                .help("Interrupt the child's current step through the official steer delivery mode")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
