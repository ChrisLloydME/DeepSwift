//
//  WorkspaceBrowserView.swift
//  DeepSwift
//

import AppKit
import PDFKit
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
            } else if let bytes = model.filePreviewBytes, let data = bytes.data,
                      let kind = model.filePreviewKind {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: kind == .pdf ? "doc.richtext" : "photo")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(fileURLWithPath: bytes.absolutePath).lastPathComponent)
                                .font(.headline)
                            Text(bytes.absolutePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        if let size = bytes.bytes {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: bytes.absolutePath))
                        } label: {
                            Label("Open Externally", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    Divider()
                    if kind == .image {
                        ZoomableImagePreview(data: data)
                    } else {
                        PDFPreview(data: data)
                    }
                }
            } else if let error = model.filePreviewError {
                ContentUnavailableView("Preview Unavailable", systemImage: "doc.questionmark", description: Text(error))
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text",
                    description: Text("Double-click a file to preview text, source, images, or PDFs. Other binary files open externally.")
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

// MARK: - Native media previews

private struct ZoomableImagePreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.backgroundColor = .textBackgroundColor

        let imageView = NSImageView()
        imageView.image = NSImage(data: data)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(origin: .zero, size: imageView.image?.size ?? NSSize(width: 640, height: 480))
        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }
        let image = NSImage(data: data)
        if imageView.image !== image {
            imageView.image = image
            imageView.frame = NSRect(origin: .zero, size: image?.size ?? NSSize(width: 640, height: 480))
        }
    }
}

private struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .textBackgroundColor
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document == nil {
            view.document = PDFDocument(data: data)
        }
        view.autoScales = true
    }
}
}
