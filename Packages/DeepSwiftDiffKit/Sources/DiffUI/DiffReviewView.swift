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
    public var onSelectionChange: ((String?) -> Void)?
    public var onClose: (() -> Void)?

    @State private var internalSelection: String?
    @State private var mode: DiffPresentationMode
    private let externalSelection: Binding<String?>?

    /// `initialFileID` remains the source-compatible way to choose the first
    /// file. Hosts that need externally controlled navigation can additionally
    /// pass `selectedFileID`; file identity is never part of the document.
    public init(
        document: DiffDocument,
        configuration: DiffReviewConfiguration = .init(),
        initialFileID: String? = nil,
        selectedFileID: Binding<String?>? = nil,
        initialMode: DiffPresentationMode? = nil,
        onSelectionChange: ((String?) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.document = document
        self.configuration = configuration
        self.externalSelection = selectedFileID
        self.onSelectionChange = onSelectionChange
        self.onClose = onClose
        let initial = selectedFileID?.wrappedValue
            ?? initialFileID
            ?? document.files.first?.id
        _internalSelection = State(initialValue: initial)
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
        .onAppear {
            if let selected = selection.wrappedValue,
               document.files.contains(where: { $0.id == selected }) {
                return
            }
            selection.wrappedValue = document.files.first?.id
        }
        .onChange(of: selection.wrappedValue) {
            onSelectionChange?(selection.wrappedValue)
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
            .accessibilityLabel("Diff presentation mode")
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
            List(selection: selection) {
                ForEach(document.files) { file in
                    DiffFileRow(file: file)
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
            DiffReviewDetailView(
                file: file,
                configuration: configuration,
                mode: $mode
            )
            .id(file.id)
        } else {
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a changed file to review its comparison.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selection: Binding<String?> {
        externalSelection ?? $internalSelection
    }

    private var selectedFile: DiffFile? {
        guard let selectedID = selection.wrappedValue else {
            return document.files.first
        }
        return document.files.first { $0.id == selectedID }
    }

    private var selectedFileIndex: Int {
        guard let selectedID = selection.wrappedValue else { return -1 }
        return document.files.firstIndex { $0.id == selectedID } ?? -1
    }

    private func selectAdjacentFile(offset: Int) {
        let current = selectedFileIndex >= 0 ? selectedFileIndex : 0
        let next = min(max(0, current + offset), document.files.count - 1)
        selection.wrappedValue = document.files[next].id
    }
}
