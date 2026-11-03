//
//  ToolCallView.swift
//  DeepSwift
//

import SwiftUI

struct ToolCallView: View {
    let card: ToolCard
    @State private var isExpanded = false
    @State private var showFullOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: card.symbolName)
                        .font(.callout)
                        .foregroundStyle(card.isError ? .red : .secondary)
                        .frame(width: 18)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.displayName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        if !card.subtitle.isEmpty {
                            Text(card.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    if !card.isComplete {
                        ProgressView()
                            .controlSize(.mini)
                    } else if card.isError {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if !card.arguments.isEmpty, card.arguments != "{}" {
                        detailSection("Arguments", text: card.prettyArguments, monospaced: true)
                    }
                    if let result = card.result, !result.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Output")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if result.components(separatedBy: .newlines).count > 30 {
                                    Button(showFullOutput ? "Show Less" : "Show All") {
                                        showFullOutput.toggle()
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                            }
                            ScrollView(.horizontal) {
                                Text(displayResult(result))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(card.isError ? .red : .primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: showFullOutput ? 460 : 220)
                        }
                    } else if card.isComplete {
                        Text("No output")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
            }
        }
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(card.isError ? AnyShapeStyle(Color.red.opacity(0.35)) : AnyShapeStyle(.separator), lineWidth: 1)
        }
    }

    private func detailSection(_ title: String, text: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Text(text)
                    .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        }
    }

    private func displayResult(_ result: String) -> String {
        guard !showFullOutput else { return result }
        let lines = result.components(separatedBy: .newlines)
        return lines.prefix(30).joined(separator: "\n")
    }
}
