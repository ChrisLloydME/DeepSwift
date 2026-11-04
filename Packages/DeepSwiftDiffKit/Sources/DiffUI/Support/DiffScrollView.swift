//
//  DiffScrollView.swift
//  DiffUI
//

import AppKit

/// NSScrollView that keeps the document view wide enough for non-wrapped code
/// while still allowing the caller to choose wrapping.
final class DiffScrollView: NSScrollView {
    var preferredContentWidth: CGFloat = 0
    var wrapsLines = false {
        didSet {
            if wrapsLines != oldValue {
                configureTextViewForWrapping()
            }
        }
    }

    override func layout() {
        super.layout()
        guard let textView = documentView as? DiffTextView else { return }
        let width = wrapsLines
            ? max(0, contentSize.width)
            : max(preferredContentWidth, contentSize.width)
        guard width > 0 else { return }
        if abs(textView.frame.width - width) > 0.5 {
            var frame = textView.frame
            frame.size.width = width
            textView.frame = frame
        }
        if wrapsLines {
            textView.textContainer?.containerSize = NSSize(
                width: max(0, width - textView.textContainerInset.width * 2),
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = true
        } else {
            textView.textContainer?.containerSize = NSSize(
                width: max(0, width - textView.textContainerInset.width * 2),
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = false
        }
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = max(contentSize.height, used.height + textView.textContainerInset.height * 2)
        if abs(textView.frame.height - height) > 0.5 {
            var frame = textView.frame
            frame.size.height = height
            textView.frame = frame
        }
    }


    private func configureTextViewForWrapping() {
        guard let textView = documentView as? DiffTextView else { return }
        textView.isHorizontallyResizable = !wrapsLines
        hasHorizontalScroller = !wrapsLines
        autohidesScrollers = true
        needsLayout = true
    }
}
