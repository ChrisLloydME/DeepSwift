//
//  DiffTextScrollView.swift
//  DiffUI
//

import AppKit
import DiffCore
import SwiftUI

enum DiffRenderKind {
    case unified
    case sideBySide
}

struct DiffTextScrollView: NSViewRepresentable {
    let file: DiffFile
    let configuration: DiffUIConfiguration
    let selectedHunk: Int
    let kind: DiffRenderKind

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DiffScrollView {
        let scrollView = DiffScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !(kind == .unified && configuration.wrapsLines)
        scrollView.autohidesScrollers = true
        scrollView.wrapsLines = kind == .unified && configuration.wrapsLines

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 0

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = DiffTextView(
            frame: NSRect(origin: .zero, size: NSSize(width: 640, height: 320)),
            textContainer: textContainer
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.setAccessibilityLabel("Diff")
        textView.setAccessibilityHelp("Select or copy the displayed diff. Use the review controls to navigate hunks.")

        scrollView.documentView = textView
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        context.coordinator.rebuildIfNeeded(file: file, configuration: configuration, kind: kind)
        context.coordinator.scroll(toHunk: selectedHunk)
        return scrollView
    }

    func updateNSView(_ scrollView: DiffScrollView, context: Context) {
        let wraps = kind == .unified && configuration.wrapsLines
        scrollView.wrapsLines = wraps
        scrollView.hasHorizontalScroller = !wraps
        context.coordinator.rebuildIfNeeded(file: file, configuration: configuration, kind: kind)
        context.coordinator.scroll(toHunk: selectedHunk)
    }

    static func dismantleNSView(_ scrollView: DiffScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var scrollView: DiffScrollView?
        weak var textView: DiffTextView?
        private var content: DiffTextContent?
        private var lastFile: DiffFile?
        private var lastConfiguration: DiffUIConfiguration?
        private var lastKind: DiffRenderKind?
        private var lastSelectedHunk: Int?

        func attach(scrollView: DiffScrollView, textView: DiffTextView) {
            self.scrollView = scrollView
            self.textView = textView
        }

        func detach() {
            textView = nil
            scrollView = nil
            content = nil
        }

        func rebuildIfNeeded(
            file: DiffFile,
            configuration: DiffUIConfiguration,
            kind: DiffRenderKind
        ) {
            guard let textView, let scrollView else { return }
            let changed = lastFile != file
                || lastConfiguration != configuration
                || lastKind != kind
            guard changed || content == nil else { return }

            let content = kind == .unified
                ? UnifiedDiffContentBuilder.make(file: file, configuration: configuration)
                : SideBySideDiffContentBuilder.make(file: file, configuration: configuration)
            self.content = content
            if lastFile != file || lastKind != kind {
                lastSelectedHunk = nil
            }
            lastFile = file
            lastConfiguration = configuration
            lastKind = kind

            textView.textStorage?.setAttributedString(content.attributed)
            textView.rowStarts = content.rowStarts
            textView.rowBackgrounds = content.backgrounds
            textView.splitX = content.backgrounds.compactMap(\.splitX).max()
            scrollView.preferredContentWidth = content.contentWidth
            scrollView.wrapsLines = kind == .unified && configuration.wrapsLines

            textView.needsDisplay = true
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
        }

        func scroll(toHunk hunkIndex: Int) {
            guard let content, let textView, let scrollView else { return }
            guard let row = content.hunkRowIndices[hunkIndex],
                  content.rowStarts.indices.contains(row) else { return }
            guard lastSelectedHunk != hunkIndex else { return }
            lastSelectedHunk = hunkIndex
            let location = content.rowStarts[row]
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
