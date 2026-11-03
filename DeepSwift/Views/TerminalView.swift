//
//  TerminalView.swift
//  DeepSwift
//

import AppKit
import SwiftTerm
import SwiftUI

/// Native terminal surface backed by the official DSH terminal controller.
/// SwiftTerm owns only VT parsing and AppKit input; the Host owns the PTY.
struct TerminalWorkspaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmTerminate = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 860, maxWidth: .infinity,
               minHeight: 460, idealHeight: 600, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: model.selectedSessionID) {
            await model.prepareTerminal()
        }
        .onDisappear {
            model.detachTerminal()
        }
        .confirmationDialog("Terminate this terminal?", isPresented: $confirmTerminate) {
            Button("Terminate", role: .destructive) {
                Task { await model.closeSelectedTerminal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The shell process and everything running in it will be stopped.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Terminal", systemImage: "terminal")
                .font(.headline)

            if !model.terminals.isEmpty {
                Picker("Terminal", selection: Binding(
                    get: { model.selectedTerminalID },
                    set: { id in Task { await model.selectTerminal(id) } }
                )) {
                    ForEach(model.terminals) { terminal in
                        Text(terminal.displayTitle).tag(terminal.id as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }

            if model.terminalLoading {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Button {
                Task { await model.createTerminal() }
            } label: {
                Label("New Terminal", systemImage: "plus")
            }
            .disabled(model.terminalLoading || model.selectedSessionID == nil)

            Button(role: .destructive) {
                confirmTerminate = true
            } label: {
                Label("Terminate", systemImage: "xmark.octagon")
            }
            .disabled(model.selectedTerminalID == nil)

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.terminalError, model.terminalSnapshot == nil {
            ContentUnavailableView {
                Label("Terminal Unavailable", systemImage: "terminal")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task { await model.prepareTerminal() }
                }
                Button("New Terminal") {
                    Task { await model.createTerminal() }
                }
            }
        } else if let snapshot = model.terminalSnapshot {
            VStack(spacing: 0) {
                if let error = model.terminalError {
                    TerminalErrorBanner(message: error) {
                        if let id = model.selectedTerminalID {
                            Task { await model.attachTerminal(id) }
                        }
                    }
                }
                TerminalPane(
                    snapshot: snapshot,
                    output: model.terminalOutput,
                    revision: model.terminalRevision,
                    cols: model.terminals.first(where: { $0.id == model.selectedTerminalID })?.cols ?? 80,
                    rows: model.terminals.first(where: { $0.id == model.selectedTerminalID })?.rows ?? 24,
                    writable: model.terminalWritable,
                    onInput: { bytes in model.sendTerminalInput(bytes) },
                    onResize: { cols, rows in model.resizeTerminal(cols: cols, rows: rows) }
                )
                .id(model.selectedTerminalID)
                .accessibilityLabel("Terminal session")
            }
        } else if model.terminalLoading {
            ProgressView("Attaching terminal…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("No Terminal", systemImage: "terminal")
            } description: {
                Text("Open a shell in this session's workspace. The process belongs to the DSH Host and remains available if you close this window.")
            } actions: {
                Button("New Terminal") {
                    Task { await model.createTerminal() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let terminal = model.terminals.first(where: { $0.id == model.selectedTerminalID }) {
                if let shell = terminal.shell {
                    Label(shell.name ?? URL(fileURLWithPath: shell.path).lastPathComponent,
                          systemImage: "terminal")
                }
                if let cwd = terminal.cwd, !cwd.isEmpty {
                    Text((cwd as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cwd)
                }
                Text(terminal.state?.capitalized ?? "Unknown")
                    .foregroundStyle(terminal.isRunning ? .green : .secondary)
                if let code = terminal.exitCode {
                    Text("Exit \(code)")
                        .foregroundStyle(.secondary)
                }
                if !model.terminalWritable {
                    Text("Read only")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No terminal attached")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private struct TerminalErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Reconnect", action: retry)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.12))
    }
}

// MARK: - SwiftTerm bridge

private struct TerminalPane: NSViewRepresentable {
    let snapshot: String
    let output: String
    let revision: Int
    let cols: Int
    let rows: Int
    let writable: Bool
    let onInput: ([UInt8]) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let view = SwiftTerm.TerminalView(frame: .zero, font: font)
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = .textBackgroundColor
        view.nativeForegroundColor = .textColor
        context.coordinator.terminalView = view
        context.coordinator.render(snapshot: snapshot, output: output, revision: revision,
                                   cols: cols, rows: rows)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(snapshot: snapshot, output: output, revision: revision,
                                   cols: cols, rows: rows)
    }

    static func dismantleNSView(_ view: SwiftTerm.TerminalView, coordinator: Coordinator) {
        view.terminalDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        var parent: TerminalPane
        weak var terminalView: SwiftTerm.TerminalView?
        private var lastRevision = -1
        private var lastSnapshot: String?
        private var lastOutputCount = 0
        private var lastCols = 0
        private var lastRows = 0
        private var applyingFrame = false

        init(parent: TerminalPane) {
            self.parent = parent
        }

        func render(snapshot: String, output: String, revision: Int, cols: Int, rows: Int) {
            guard let terminalView, revision != lastRevision else { return }
            let terminal = terminalView.getTerminal()
            let freshSnapshot = snapshot != lastSnapshot
            if freshSnapshot {
                applyingFrame = true
                terminal.resetToInitialState()
                if cols != lastCols || rows != lastRows {
                    terminalView.resize(cols: cols, rows: rows)
                    lastCols = cols
                    lastRows = rows
                }
                terminalView.feed(text: snapshot)
                lastSnapshot = snapshot
                lastOutputCount = 0
                applyingFrame = false
            } else if output.count > lastOutputCount {
                let start = output.index(output.startIndex, offsetBy: lastOutputCount)
                terminalView.feed(text: String(output[start...]))
                lastOutputCount = output.count
            }
            lastRevision = revision
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard !applyingFrame else { return }
            lastCols = newCols
            lastRows = newRows
            parent.onResize(newCols, newRows)
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            guard parent.writable else { return }
            parent.onInput(Array(data))
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            guard let string = String(data: content, encoding: .utf8) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}

        func bell(source: SwiftTerm.TerminalView) {
            NSSound.beep()
        }
    }
}

#if DEBUG
#Preview("Terminal Surface") {
    TerminalPane(
        snapshot: "\u{1B}[32muser@mac\u{1B}[0m project % echo hello\r\nhello\r\n\u{1B}[32muser@mac\u{1B}[0m project % ",
        output: "",
        revision: 1,
        cols: 80,
        rows: 24,
        writable: true,
        onInput: { _ in },
        onResize: { _, _ in }
    )
    .frame(width: 760, height: 440)
    .padding(16)
    .background(Color(nsColor: .textBackgroundColor))
}
#endif
