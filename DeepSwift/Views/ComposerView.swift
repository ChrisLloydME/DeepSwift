//
//  ComposerView.swift
//  DeepSwift
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("sendOnEnter") private var sendOnEnter = true
    @State private var editorHeight: CGFloat = 86
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            if !model.commandSuggestions.isEmpty {
                commandSuggestions
            }
            if !model.attachments.isEmpty {
                attachmentStrip
            }
            ZStack(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text("Message DeepSeek…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                ComposerTextView(
                    text: $model.draft,
                    sendOnEnter: sendOnEnter,
                    onSubmit: submit,
                    onHeightChange: { height in
                        if abs(editorHeight - height) > 0.5 {
                            editorHeight = height
                        }
                    }
                )
                .frame(height: editorHeight)
            }

            HStack(spacing: 10) {
                Button {
                    chooseImages()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Attach Images")
                .disabled(model.attachments.count >= 8)

                Text("↩ \(sendOnEnter ? "send" : "newline") · ⇧↩ \(sendOnEnter ? "newline" : "send")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if model.selectedSession?.isRunning == true {
                    Button {
                        Task { await model.cancelCurrentTurn() }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Stop Generation (⌘.)")
                }
                Button {
                    submit()
                } label: {
                    if model.isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isSending || (model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.attachments.isEmpty))
                .help("Send (⌘↩)")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                Task { await model.attachImage(at: url) }
            }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var commandSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.commandSuggestions) { command in
                Button {
                    model.applyCommandSuggestion(command)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(command.slashName)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text(command.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .background(.quaternary.opacity(0.12))
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        if let image = NSImage(data: attachment.data) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(.quaternary)
                                .frame(width: 52, height: 52)
                                .overlay { Image(systemName: "photo") }
                        }
                        Button {
                            model.removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white, .black.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                        .padding(2)
                        .accessibilityLabel("Remove image \(attachment.name)")
                    }
                    .help(attachment.name)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Attach Images"
        panel.prompt = "Attach"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            Task { await model.attachImage(at: url) }
        }
    }

    private func submit() {
        guard !model.isSending else { return }
        let hasText = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || !model.attachments.isEmpty else { return }
        Task { await model.sendMessage() }
    }
}

/// AppKit-backed multi-line composer with native IME and selection behavior.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var sendOnEnter: Bool
    var onSubmit: () -> Void
    var onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 70)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.textContainer?.lineFragmentPadding = 6
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFindBar = true
        textView.string = text
        textView.setAccessibilityLabel("Message")
        textView.setAccessibilityHelp("Type a message to DeepSeek. Return sends; Shift-Return inserts a newline.")

        context.coordinator.textView = textView
        scrollView.documentView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.recalculateHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        // Never replace marked text: doing so breaks the input method's
        // composition session for Chinese, Japanese, and Korean input.
        guard !textView.hasMarkedText(), textView.string != text else { return }
        let previous = textView.selectedRange()
        textView.string = text
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(previous.location, length), length: 0))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else { return }
            let value = textView.string
            Task { @MainActor in
                self.parent.text = value
            }
            recalculateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            guard !textView.hasMarkedText() else { return false }
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            if modifiers.contains(.shift) {
                return false
            }
            if !parent.sendOnEnter && !modifiers.contains(.command) {
                return false
            }
            parent.onSubmit()
            return true
        }

        func recalculateHeight() {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            let inset = textView.textContainerInset.height * 2
            let height = min(max(used.height + inset + 4, 70), 220)
            self.parent.onHeightChange(height)
        }
    }
}
