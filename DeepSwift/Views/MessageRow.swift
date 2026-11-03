//
//  MessageRow.swift
//  DeepSwift
//

import AppKit
import SwiftUI

struct MessageRow: View {
    let item: ChatItem
    let showTimestamp: Bool

    var body: some View {
        switch item.kind {
        case let .user(text):
            userMessage(text)
        case let .assistant(text, reasoning):
            assistantMessage(text: text, reasoning: reasoning)
        case let .tool(card):
            ToolCallView(card: card)
        case let .notice(text):
            notice(text, systemImage: "info.circle", color: .secondary)
        case let .error(text):
            notice(text, systemImage: "exclamationmark.triangle", color: .red)
        }
    }

    private func userMessage(_ text: String) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 90)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color.accentColor.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .contextMenu {
                        Button("Copy") { copy(text) }
                    }
                if showTimestamp {
                    timestamp
                }
            }
        }
    }

    private func assistantMessage(text: String, reasoning: String?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let reasoning, !reasoning.isEmpty {
                DisclosureGroup {
                    Text(reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Label("Reasoning", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if text.isEmpty {
                Text("No response content")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                MarkdownTextView(text: text)
                    .contextMenu {
                        Button("Copy") { copy(text) }
                    }
            }
            if showTimestamp {
                timestamp
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func notice(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
                .textSelection(.enabled)
        }
        .font(.callout)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    private var timestamp: some View {
        Text(item.time, format: .dateTime.hour().minute())
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
