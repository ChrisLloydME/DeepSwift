//
//  WorkspaceBrowserView.swift
//  DeepSwift
//

import AppKit
import SwiftUI

/// Native workspace browser backed by the official `workspaceFiles` Remote.
/// The Host enforces workspace containment; this view never reads files itself.
struct WorkspaceBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEntry: WorkspaceFileEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                fileList
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 380)
                preview
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            if model.fileListing == nil {
                await model.loadFiles()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.loadFilesParent() }
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(model.filesPath.isEmpty)
            .help("Parent Folder")

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(breadcrumb)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.filesPath.isEmpty ? "Workspace Root" : model.filesPath)

            if model.isLoadingFiles {
                ProgressView().controlSize(.mini)
            }

            Spacer()

            Button {
                Task { await model.loadFiles(path: model.filesPath) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload Folder")

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var breadcrumb: String {
        model.filesPath.isEmpty ? "Workspace Root" : model.filesPath
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            if let error = model.filePreviewError, model.fileListing == nil {
                ContentUnavailableView("Workspace Unavailable", systemImage: "folder.badge.questionmark", description: Text(error))
            } else {
                List(selection: $selectedEntry) {
                    ForEach(sortedEntries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? "folder" : fileSymbol(entry.name))
                                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name)
                                    .lineLimit(1)
                                if let size = entry.size, !entry.isDirectory {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .tag(entry)
                        .onTapGesture(count: 2) {
                            open(entry)
                        }
                        .contextMenu {
                            Button("Open") { open(entry) }
                            Button("Reveal in Finder") {
                                let path = model.filesPath.isEmpty ? entry.name : "\(model.filesPath)/\(entry.name)"
                                reveal(path)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if sortedEntries.isEmpty && !model.isLoadingFiles {
                        ContentUnavailableView("Empty Folder", systemImage: "folder")
                    }
                }
            }

            if let listing = model.fileListing, listing.truncated {
                Text("Showing the first entries; the folder contains more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }

    private var preview: some View {
        Group {
            if let preview = model.filePreview {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: fileSymbol(preview.absolutePath))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(fileURLWithPath: preview.absolutePath).lastPathComponent)
                                .font(.headline)
                            Text(preview.absolutePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        if let bytes = preview.bytes {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: preview.absolutePath))
                        } label: {
                            Label("Open Externally", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(preview.text, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    Divider()
                    ScrollView([.vertical, .horizontal]) {
                        Text(numbered(preview.text))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if preview.eof == false {
                        Text("Only the first page is shown. Use the Host file tools for larger files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.3))
                    }
                }
            } else if let error = model.filePreviewError {
                ContentUnavailableView("Preview Unavailable", systemImage: "doc.questionmark", description: Text(error))
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text",
                    description: Text("Double-click a file to preview it. Image and PDF previews are not available in this build.")
                )
            }
        }
    }

    private var sortedEntries: [WorkspaceFileEntry] {
        (model.fileListing?.entries ?? []).sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func open(_ entry: WorkspaceFileEntry) {
        selectedEntry = entry
        if entry.isDirectory {
            let next = model.filesPath.isEmpty ? entry.name : "\(model.filesPath)/\(entry.name)"
            Task { await model.loadFiles(path: next) }
        } else {
            Task { await model.openFile(entry) }
        }
    }

    private func reveal(_ path: String) {
        guard let workspacePath = model.selectedWorkspace?.path ?? model.selectedSession?.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspacePath).appendingPathComponent(path)])
    }

    private func numbered(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let width = String(lines.count).count
        return lines.enumerated().map { index, line in
            let number = String(index + 1)
            let padding = String(repeating: " ", count: max(0, width - number.count))
            return "\(padding)\(number)  \(line)"
        }.joined(separator: "\n")
    }

    private func fileSymbol(_ name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "swift": return "swift"
        case "md", "txt", "rtf": return "doc.text"
        case "json", "yml", "yaml", "toml", "xml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "pdf": return "doc.richtext"
        case "sh", "zsh", "bash": return "terminal"
        default: return "doc"
        }
    }
}
