//
//  ApprovalRequestView.swift
//  DeepSwift
//

import SwiftUI

struct ApprovalRequestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let approval: PendingApproval
    @State private var isResponding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permission Request")
                        .font(.title3.weight(.semibold))
                    Text("DeepSeek wants to use \(approval.toolName.isEmpty ? "a tool" : approval.toolName).")
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = approval.localizedReason, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reason")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(reason)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if approval.toolName.isEmpty || approval.sessionId.isEmpty {
                Label("This request could not be fully identified. Rejecting is the safe choice.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text("Approval grants one operation only. It does not change this session's permission policy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Reject", role: .destructive) {
                    respond("rejected")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isResponding)

                Button("Allow Once") {
                    respond("allowed-once")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isResponding)

                if isResponding {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(22)
        .frame(width: 480)
        .interactiveDismissDisabled()
        .onDisappear {
            // Dismissal without an explicit decision fails closed.
            if !isResponding {
                Task { await model.respondApproval(approval, outcome: "cancelled") }
            }
        }
    }

    private func respond(_ outcome: String) {
        guard !isResponding else { return }
        isResponding = true
        Task {
            await model.respondApproval(approval, outcome: outcome)
            dismiss()
        }
    }
}

struct QuestionRequestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let question: PendingQuestion
    @State private var selections: [String: Set<String>]
    @State private var custom: [String: String] = [:]
    @State private var isResponding = false

    init(question: PendingQuestion) {
        self.question = question
        var initial: [String: Set<String>] = [:]
        for item in question.questions { initial[item.id] = [] }
        _selections = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "questionmark.bubble")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(questionHeader)
                        .font(.title3.weight(.semibold))
                    Text("DeepSeek needs your input to continue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(question.questions) { item in
                        questionView(item)
                    }
                }
                .padding(22)
            }
            .frame(maxHeight: 480)

            Divider()

            HStack {
                Button("Cancel Request", role: .cancel) {
                    cancel()
                }
                .disabled(isResponding)
                Spacer()
                Button("Submit") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isResponding || !isAnswered)
                if isResponding {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(16)
        }
        .frame(width: 560)
        .interactiveDismissDisabled()
    }

    private var questionHeader: String {
        question.questions.first?.header ?? (question.questions.first?.isPlanReview == true ? "Plan Review" : "Question")
    }

    @ViewBuilder
    private func questionView(_ item: AskQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = item.header, header != questionHeader {
                Text(header.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(item.question)
                .font(.headline)
                .textSelection(.enabled)

            if let detail = item.detail, !detail.isEmpty {
                ScrollView {
                    MarkdownTextView(text: detail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: item.isPlanReview ? 260 : 160)
                .padding(10)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }

            ForEach(Array((item.options ?? []).enumerated()), id: \.offset) { _, option in
                optionRow(item: item, option: option)
            }

            TextField("Other answer (optional)", text: Binding(
                get: { custom[item.id] ?? "" },
                set: { custom[item.id] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private func optionRow(item: AskQuestion, option: AskQuestionOption) -> some View {
        let selected = selections[item.id]?.contains(option.label) == true
        return Button {
            toggle(item: item, option: option)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(8)
            .background(
                selected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggle(item: AskQuestion, option: AskQuestionOption) {
        if item.multiSelect == true {
            var current = selections[item.id] ?? []
            if current.contains(option.label) { current.remove(option.label) }
            else { current.insert(option.label) }
            selections[item.id] = current
        } else {
            selections[item.id] = [option.label]
        }
    }

    private var isAnswered: Bool {
        question.questions.allSatisfy { item in
            !(selections[item.id] ?? []).isEmpty || !(custom[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() {
        guard !isResponding else { return }
        isResponding = true
        let answers: [[String: JSONValue]] = question.questions.map { item in
            var answer: [String: JSONValue] = [
                "id": .string(item.id),
                "selected": .array((selections[item.id] ?? []).sorted().map(JSONValue.string))
            ]
            let text = (custom[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { answer["custom"] = .string(text) }
            return answer
        }
        Task {
            await model.respondQuestion(question, answers: answers)
            dismiss()
        }
    }

    private func cancel() {
        guard !isResponding else { return }
        isResponding = true
        Task {
            await model.cancelQuestion(question)
            dismiss()
        }
    }
}
