//
//  WorkspaceChangesView.swift
//  DeepSwift
//

import SwiftUI

/// Native changed-files summary and unified diff viewer for one completed turn.
struct WorkspaceChangesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var diff: WorkspaceFileDiff?
    @State private var diffLoading = false
    @State private var diffError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let summary = model.changesSummary {
                HSplitView {
                    fileList(summary)
                        .frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
                    diffDetail
                        .frame(minWidth: 480, maxWidth: .infinity)
                }
            } else if model.changesLoading {
                Spacer()
                ProgressView("Loading changed files…")
                Spacer()
            } else {
                ContentUnavailableView {
                    Label("No Changed Files", systemImage: "plus.forwardslash.minus")
                } description: {
                    Text(model.changesError ?? "The latest turn did not report file changes.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 780, idealWidth: 900, minHeight: 500, idealHeight: 620)
        .task(id: model.changesSummary?.turn) {
            selectedIndex = 0
            await loadDiff()
        }
        .onChange(of: selectedIndex) {
            Task { await loadDiff() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Changes", systemImage: "plus.forwardslash.minus")
                .font(.headline)
            if let summary = model.changesSummary {
                Text("Turn \(summary.turn)")
                    .foregroundStyle(.secondary)
                Text("\(summary.files.count) of \(summary.total) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("+\(summary.added)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.green)
                Text("−\(summary.deleted)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func fileList(_ summary: WorkspaceChangesSummary) -> some View {
        List(selection: $selectedIndex) {
            ForEach(Array(summary.files.enumerated()), id: \.offset) { index, file in
                HStack(spacing: 6) {
                    Image(systemName: file.binary == true ? "doc.badge.gearshape" : "doc.text")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.display)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(file.path)
                        if file.binary == true || file.oversized == true {
                            Text(file.oversized == true ? "Too large to compare" : "Binary")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if file.added > 0 {
                        Text("+\(file.added)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if file.deleted > 0 {
                        Text("−\(file.deleted)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
                .contentShape(Rectangle())
                .tag(index)
            }
        }
        .listStyle(.inset)
    }

    private var diffDetail: some View {
        Group {
            if diffLoading {
                ProgressView("Loading comparison…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = diffError {
                ContentUnavailableView("Comparison Unavailable", systemImage: "doc.questionmark", description: Text(error))
            } else if let diff {
                switch diff.kind {
                case "binary":
                    ContentUnavailableView("Binary File", systemImage: "doc.badge.gearshape",
                                           description: Text("This file has no textual comparison."))
                case "oversized":
                    ContentUnavailableView("File Too Large", systemImage: "doc.badge.clock",
                                           description: Text("The Host did not retain a comparison for this file."))
                default:
                    diffScroll(diff)
                }
            } else {
                ContentUnavailableView("Select a File", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Choose a changed file to review its comparison."))
            }
        }
    }

    private func diffScroll(_ diff: WorkspaceFileDiff) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(diff.display)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if diff.coarse == true {
                    Text("Coarse comparison")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("The line comparison exceeded the Host time limit and shows whole-file replacement.")
                }
            }
            .padding(10)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((diff.hunks ?? []).enumerated()), id: \.offset) { _, hunk in
                        Text("@@ -\(hunk.oldStart),\(hunk.oldLines) +\(hunk.newStart),\(hunk.newLines) @@")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35))
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineRow(line: line)
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(minWidth: 640, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let summary = model.changesSummary, !summary.files.isEmpty {
                Button {
                    selectedIndex = max(0, selectedIndex - 1)
                } label: {
                    Label("Previous File", systemImage: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex <= 0)
                Button {
                    selectedIndex = min(summary.files.count - 1, selectedIndex + 1)
                } label: {
                    Label("Next File", systemImage: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex >= summary.files.count - 1)
                Text("File \(selectedIndex + 1) of \(summary.files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let summary = model.changesSummary, let cwd = summary.cwd {
                Text((cwd as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(cwd)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func loadDiff() async {
        guard let summary = model.changesSummary,
              summary.files.indices.contains(selectedIndex) else {
            diff = nil
            diffError = nil
            return
        }
        let requestedIndex = selectedIndex
        diffLoading = true
        diffError = nil
        diff = nil
        do {
            let loaded = try await model.loadChangesDiff(index: requestedIndex)
            guard selectedIndex == requestedIndex else { return }
            diff = loaded
            diffLoading = false
        } catch {
            guard selectedIndex == requestedIndex else { return }
            diffError = error.localizedDescription
            diffLoading = false
        }
    }
}

private struct DiffLineRow: View {
    let line: String

    var body: some View {
        let prefix = line.first
        let color: Color = prefix == "+" ? .green : prefix == "-" ? .red : .primary
        HStack(alignment: .top, spacing: 0) {
            Text(String(prefix ?? " "))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .center)
            Text(String(line.dropFirst()))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(prefix == "+" ? Color.green.opacity(0.10) : prefix == "-" ? Color.red.opacity(0.10) : Color.clear)
    }
}

struct WorkspaceChangesCard: View {
    let summary: WorkspaceChangesSummary
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.forwardslash.minus")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.files.count == 1 ? "1 file changed" : "\(summary.files.count) files changed")
                    .font(.callout.weight(.medium))
                HStack(spacing: 8) {
                    Text("+\(summary.added)")
                        .foregroundStyle(.green)
                    Text("−\(summary.deleted)")
                        .foregroundStyle(.red)
                    Text(summary.files.prefix(3).map(\.display).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
            }
            Spacer()
            Button("Review…", action: open)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: 860)
    }
}

#if DEBUG
#Preview("Changed Files Card") {
    WorkspaceChangesCard(
        summary: WorkspaceChangesSummary(
            turn: 3,
            cwd: "/Users/example/Project",
            files: [
                WorkspaceChangedFile(path: "Sources/App.swift", display: "Sources/App.swift", added: 24, deleted: 8, binary: nil, oversized: nil),
                WorkspaceChangedFile(path: "README.md", display: "README.md", added: 3, deleted: 1, binary: nil, oversized: nil),
                WorkspaceChangedFile(path: "Assets/logo.png", display: "Assets/logo.png", added: 0, deleted: 0, binary: true, oversized: nil)
            ],
            total: 3,
            added: 27,
            deleted: 9
        ),
        open: {}
    )
    .padding(24)
    .frame(width: 760)
}
#endif
