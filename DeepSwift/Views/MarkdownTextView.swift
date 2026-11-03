//
//  MarkdownTextView.swift
//  DeepSwift
//

import AppKit
import SwiftUI

/// Small, native Markdown presentation layer.
///
/// Inline formatting and links use `AttributedString`; block structure is
/// rendered explicitly so headings, lists, quotes, fenced code, and tables
/// keep their native spacing and selection behavior.
struct MarkdownTextView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level, content):
            Text(inline(content))
                .font(headingFont(level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 2)
        case let .paragraph(content):
            Text(inline(content))
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(content, depth):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(inline(content))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case let .numbered(number, content, depth):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(inline(content))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case let .quote(content):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(inline(content))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .code(language, code):
            CodeBlockView(language: language, code: code)
        case let .table(rows):
            MarkdownTableView(rows: rows)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.semibold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    private func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, content: String)
        case paragraph(String)
        case bullet(content: String, depth: Int)
        case numbered(number: Int, content: String, depth: Int)
        case quote(String)
        case code(language: String?, code: String)
        case table([[String]])
    }

    let id: Int
    let kind: Kind

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func append(_ kind: Kind) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind))
        }

        func flushParagraph() {
            let content = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { append(.paragraph(content)) }
            paragraph.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                append(.code(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")))
                continue
            }

            if isTableRow(trimmed), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()
                var rows: [[String]] = [cells(trimmed)]
                index += 2
                while index < lines.count, isTableRow(lines[index].trimmingCharacters(in: .whitespaces)) {
                    rows.append(cells(lines[index].trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                append(.table(rows))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let heading = headingContent(trimmed) {
                flushParagraph()
                append(.heading(level: heading.level, content: heading.content))
                index += 1
                continue
            }

            let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.count
            let depth = max(0, leadingSpaces / 2)

            if let content = bulletContent(trimmed) {
                flushParagraph()
                append(.bullet(content: content, depth: depth))
                index += 1
                continue
            }

            if let numbered = numberedContent(trimmed) {
                flushParagraph()
                append(.numbered(number: numbered.number, content: numbered.content, depth: depth))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    private static func headingContent(_ line: String) -> (level: Int, content: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.hasPrefix(" ") else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedContent(_ line: String) -> (number: Int, content: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return (number, String(rest.dropFirst(2)))
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.filter { $0 == "|" }.count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isTableRow(trimmed) else { return false }
        return cells(trimmed).allSatisfy { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            return !value.isEmpty && value.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    private static func cells(_ line: String) -> [String] {
        var value = line
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.35))

            Divider()

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
    }
}

private struct MarkdownTableView: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(.init(cell))
                                .font(rowIndex == 0 ? .callout.weight(.semibold) : .callout)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(.separator).frame(height: 1)
                                }
                        }
                    }
                    .background(rowIndex == 0 ? Color.secondary.opacity(0.08) : Color.clear)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
    }
}
