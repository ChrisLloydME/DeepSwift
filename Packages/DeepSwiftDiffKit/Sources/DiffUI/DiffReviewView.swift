//
//  DiffReviewView.swift
//  DiffUI
//

import DiffCore
import SwiftUI

/// Full Diff review content. The host application is responsible for placing
/// this view in a standard macOS window, sheet, or other container. It does not
/// create a window or fetch comparisons.
public struct DiffReviewView: View {
    public let document: DiffDocument
    public let configuration: DiffReviewConfiguration
    public var onClose: (() -> Void)?

    @State private var selectedFileID: String?
    @State private var mode: DiffPresentationMode
    @State private var selectedHunk = 0

    public init(
        document: DiffDocument,
        configuration: DiffReviewConfiguration = .init(),
        initialFileID: String? = nil,
        initialMode: DiffPresentationMode? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.document = document
        self.configuration = configuration
        self.onClose = onClose
        _selectedFileID = State(initialValue: initialFileID ?? document.files.first?.id)
        _mode = State(initialValue: initialMode ?? configuration.defaultMode)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if document.files.isEmpty {
                ContentUnavailableView(
                    "No Changed Files",
                    systemImage: "plus.forwardslash.minus",
                    description: Text("This Diff document contains no files.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if configuration.showsFileNavigator {
                HSplitView {
                    fileList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 330)
                    detail
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedFileID) {
            selectedHunk = 0
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Changes", systemImage: "plus.forwardslash.minus")
                .font(.headline)
            if let turn = document.summary.turn {
                Text("Turn \(turn)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(document.summary.total == 1 ? "1 file" : "\(document.summary.total) files")
                .font(.caption)
                .foregroundStyle(.secondary)
            DiffStatLabels(added: document.summary.added, deleted: document.summary.deleted)
            Spacer()
            Picker("Presentation", selection: $mode) {
                ForEach(DiffPresentationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("Choose Unified or Side-by-Side Diff")
            if let onClose {
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedFileID) {
                ForEach(document.files) { file in
                    DiffReviewFileRow(file: file)
                        .tag(file.id)
                }
            }
            .listStyle(.inset)
            Divider()
            HStack(spacing: 8) {
                Button {
                    selectAdjacentFile(offset: -1)
                } label: {
                    Label("Previous File", systemImage: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(selectedFileIndex <= 0)
                Button {
                    selectAdjacentFile(offset: 1)
                } label: {
                    Label("Next File", systemImage: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(selectedFileIndex < 0 || selectedFileIndex >= document.files.count - 1)
                Spacer()
                if selectedFileIndex >= 0 {
                    Text("\(selectedFileIndex + 1) of \(document.files.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let file = selectedFile {
            VStack(spacing: 0) {
                DiffFileHeaderView(file: file)
                Divider()
                if file.hunks.isEmpty || file.isBinary || file.isOversized || file.isUnavailable {
                    DiffUnavailableState(file: file)
                } else {
                    hunkToolbar(for: file)
                    Divider()
                    if mode == .unified {
                        UnifiedDiffView(
                            file: file,
                            selectedHunk: selectedHunk,
                            configuration: configuration.diff
                        )
                    } else {
                        SideBySideDiffView(
                            file: file,
                            selectedHunk: selectedHunk,
                            configuration: configuration.diff
                        )
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a changed file to review its comparison.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hunkToolbar(for file: DiffFile) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedHunk = max(0, selectedHunk - 1)
            } label: {
                Label("Previous Hunk", systemImage: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(selectedHunk <= 0)

            Button {
                selectedHunk = min(file.hunks.count - 1, selectedHunk + 1)
            } label: {
                Label("Next Hunk", systemImage: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(selectedHunk >= file.hunks.count - 1)

            if file.hunks.isEmpty == false {
                Text("Hunk \(selectedHunk + 1) of \(file.hunks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if file.isCoarse {
                Text("Coarse comparison")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.18))
    }

    private var selectedFile: DiffFile? {
        guard let selectedFileID else { return document.files.first }
        return document.files.first { $0.id == selectedFileID }
    }

    private var selectedFileIndex: Int {
        guard let selectedFileID else { return -1 }
        return document.files.firstIndex { $0.id == selectedFileID } ?? -1
    }

    private func selectAdjacentFile(offset: Int) {
        let current = selectedFileIndex >= 0 ? selectedFileIndex : 0
        let next = min(max(0, current + offset), document.files.count - 1)
        selectedFileID = document.files[next].id
    }
}

private struct DiffReviewFileRow: View {
    let file: DiffFile

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.display)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
                if file.state != .modified {
                    Text(file.stateLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            DiffStatLabels(added: file.added, deleted: file.deleted)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(
            "\(file.display), \(file.stateLabel), \(file.added) additions, \(file.deleted) deletions"
        )
    }

    private var icon: String {
        switch file.state {
        case .binary: "doc.badge.gearshape"
        case .oversized: "doc.badge.clock"
        case .unavailable: "doc.questionmark"
        case .added: "doc.badge.plus"
        case .deleted: "doc.badge.minus"
        case .empty, .modified, .coarse: "doc.text"
        }
    }
}
