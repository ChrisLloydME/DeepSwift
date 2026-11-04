//
//  DiffContentBuilders.swift
//  DiffUI
//

import AppKit
import DiffCore

enum UnifiedDiffContentBuilder {
    static func make(file: DiffFile, configuration: DiffUIConfiguration) -> DiffTextContent {
        let rows = UnifiedDiffBuilder.rows(
            for: file,
            intraline: configuration.intraline
        )
        let result = NSMutableAttributedString()
        var starts: [Int] = []
        var backgrounds: [DiffRowBackground] = []
        var hunkRowIndices: [Int: Int] = [:]
        var maximumWidth: CGFloat = 0
        let appearance = NSApp.effectiveAppearance
        let numbers = numberWidth(for: file)

        for (rowIndex, row) in rows.enumerated() {
            starts.append(result.length)
            switch row.content {
            case let .hunkHeader(index, header):
                hunkRowIndices[index] = rowIndex
                let attributes = DiffTextStyle.lineAttributes(
                    fontSize: configuration.fontSize,
                    appearance: appearance,
                    isHeader: true
                )
                result.append(NSAttributedString(string: header + "\n", attributes: attributes))
                backgrounds.append(.full(DiffPalette.hunkBackground(for: appearance)))
                maximumWidth = max(maximumWidth, measuredWidth(header, fontSize: configuration.fontSize, isHeader: true))

            case let .line(line):
                let attributes = DiffTextStyle.lineAttributes(
                    fontSize: configuration.fontSize,
                    appearance: appearance
                )
                let prefix = linePrefix(
                    for: line,
                    width: configuration.showsLineNumbers ? numbers : 0,
                    showsNumbers: configuration.showsLineNumbers
                )
                let display = prefix + line.text
                let lineStart = result.length
                result.append(NSAttributedString(string: display + "\n", attributes: attributes))

                let prefixLength = (prefix as NSString).length
                if !prefix.isEmpty {
                    let prefixRange = NSRange(location: lineStart, length: prefixLength)
                    result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
                    let markerLocation = lineStart + (prefix as NSString).range(of: marker(for: line.kind)).location
                    if markerLocation >= lineStart {
                        result.addAttribute(
                            .foregroundColor,
                            value: DiffPalette.markerColor(for: line.kind),
                            range: NSRange(location: markerLocation, length: 1)
                        )
                    }
                }

                if configuration.showsSyntaxHighlighting, !line.text.isEmpty {
                    applySyntaxHighlighting(
                        to: result,
                        line: line.text,
                        at: lineStart + prefixLength
                    )
                }
                applyIntraline(
                    to: result,
                    spans: row.intralineSpans,
                    at: lineStart + prefixLength,
                    isAddition: line.kind == .addition
                )
                backgrounds.append(background(for: line.kind, appearance: appearance))
                maximumWidth = max(
                    maximumWidth,
                    measuredWidth(display, fontSize: configuration.fontSize)
                )
            }
        }

        return DiffTextContent(
            attributed: result,
            rowStarts: starts,
            backgrounds: backgrounds,
            hunkRowIndices: hunkRowIndices,
            contentWidth: max(320, maximumWidth + 28)
        )
    }

    private static func background(for kind: DiffLineKind, appearance: NSAppearance) -> DiffRowBackground {
        switch kind {
        case .addition: .full(DiffPalette.additionBackground(for: appearance))
        case .deletion: .full(DiffPalette.deletionBackground(for: appearance))
        case .unknown: .full(DiffPalette.unknownBackground(for: appearance))
        case .context: .none
        }
    }

    private static func numberWidth(for file: DiffFile) -> Int {
        let maximum = file.hunks.reduce(1) { current, hunk in
            max(current, hunk.oldStart + hunk.oldLines, hunk.newStart + hunk.newLines)
        }
        return max(3, String(maximum).count)
    }

    private static func marker(for kind: DiffLineKind) -> String {
        switch kind {
        case .addition: "+"
        case .deletion: "−"
        case .context: " "
        case .unknown: "?"
        }
    }

    private static func linePrefix(
        for line: DiffLine,
        width: Int,
        showsNumbers: Bool
    ) -> String {
        guard showsNumbers else { return marker(for: line.kind) + " " }
        let old = line.oldLineNumber.map(String.init) ?? ""
        let new = line.newLineNumber.map(String.init) ?? ""
        let oldPadding = String(repeating: " ", count: max(0, width - old.count))
        let newPadding = String(repeating: " ", count: max(0, width - new.count))
        return oldPadding + old + " " + newPadding + new + " " + marker(for: line.kind) + " │ "
    }

    private static func measuredWidth(_ text: String, fontSize: CGFloat, isHeader: Bool = false) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: isHeader
                ? DiffPalette.codeFont(size: max(9, fontSize - 1), weight: .medium)
                : DiffPalette.codeFont(size: fontSize)
        ]
        return (text as NSString).size(withAttributes: attributes).width
    }

    private static func applySyntaxHighlighting(
        to string: NSMutableAttributedString,
        line: String,
        at offset: Int
    ) {
        for token in SwiftSyntaxHighlighter.tokens(in: line) {
            let range = NSRange(
                location: offset + token.span.location,
                length: token.span.length
            )
            guard NSMaxRange(range) <= string.length else { continue }
            string.addAttribute(
                .foregroundColor,
                value: DiffPalette.syntaxColor(for: token.kind),
                range: range
            )
        }
    }

    private static func applyIntraline(
        to string: NSMutableAttributedString,
        spans: [DiffTextSpan],
        at offset: Int,
        isAddition: Bool
    ) {
        guard !spans.isEmpty else { return }
        let color = isAddition
            ? DiffPalette.intralineAddition(for: NSApp.effectiveAppearance)
            : DiffPalette.intralineDeletion(for: NSApp.effectiveAppearance)
        for span in spans {
            let range = NSRange(location: offset + span.location, length: span.length)
            guard NSMaxRange(range) <= string.length else { continue }
            string.addAttribute(.backgroundColor, value: color, range: range)
        }
    }
}

enum SideBySideDiffContentBuilder {
    private struct PreparedRow {
        enum Kind {
            case header(String)
            case pair(left: String, right: String, leftLine: DiffLine?, rightLine: DiffLine?)
            case unknown(String)
        }

        let kind: Kind
        let leftSpans: [DiffTextSpan]
        let rightSpans: [DiffTextSpan]
        let hunkIndex: Int
    }

    static func make(file: DiffFile, configuration: DiffUIConfiguration) -> DiffTextContent {
        let rows = SideBySideDiffBuilder.rows(
            for: file,
            intraline: configuration.intraline
        )
        let appearance = NSApp.effectiveAppearance
        let numberWidth = numberWidth(for: file)
        let prefixWidth = configuration.showsLineNumbers ? 2 + numberWidth + 1 : 2
        let placeholder = String(repeating: " ", count: prefixWidth)
        let prepared: [PreparedRow] = rows.map { row in
            switch row.content {
            case let .hunkHeader(index, header):
                return PreparedRow(
                    kind: .header(header),
                    leftSpans: [],
                    rightSpans: [],
                    hunkIndex: index
                )
            case let .pair(left, right):
                return PreparedRow(
                    kind: .pair(
                        left: left.map {
                            prefix(
                                for: $0.line,
                                width: numberWidth,
                                showsNumbers: configuration.showsLineNumbers
                            ) + $0.line.text
                        } ?? placeholder,
                        right: right.map {
                            prefix(
                                for: $0.line,
                                width: numberWidth,
                                showsNumbers: configuration.showsLineNumbers
                            ) + $0.line.text
                        } ?? placeholder,
                        leftLine: left?.line,
                        rightLine: right?.line
                    ),
                    leftSpans: left?.intralineSpans ?? [],
                    rightSpans: right?.intralineSpans ?? [],
                    hunkIndex: row.hunkIndex
                )
            case let .unknown(line):
                return PreparedRow(
                    kind: .unknown(line.text),
                    leftSpans: [],
                    rightSpans: [],
                    hunkIndex: row.hunkIndex
                )
            }
        }

        let font = DiffPalette.codeFont(size: configuration.fontSize)
        let measureAttributes: [NSAttributedString.Key: Any] = [.font: font]
        var maximumLeftWidth: CGFloat = 0
        var maximumRightWidth: CGFloat = 0
        for row in prepared {
            if case let .pair(left, right, _, _) = row.kind {
                maximumLeftWidth = max(maximumLeftWidth, (left as NSString).size(withAttributes: measureAttributes).width)
                maximumRightWidth = max(maximumRightWidth, (right as NSString).size(withAttributes: measureAttributes).width)
            }
        }
        let tabLocation = max(120, ceil(maximumLeftWidth + 22))
        let separator = "│ "
        let separatorWidth = (separator as NSString).size(withAttributes: measureAttributes).width
        let contentWidth = max(360, tabLocation + separatorWidth + maximumRightWidth + 28)

        let result = NSMutableAttributedString()
        var starts: [Int] = []
        var backgrounds: [DiffRowBackground] = []
        var hunkRowIndices: [Int: Int] = [:]

        for row in prepared {
            starts.append(result.length)
            switch row.kind {
            case let .header(header):
                hunkRowIndices[row.hunkIndex] = starts.count - 1
                let attributes = DiffTextStyle.lineAttributes(
                    fontSize: configuration.fontSize,
                    appearance: appearance,
                    isHeader: true
                )
                result.append(NSAttributedString(string: header + "\n", attributes: attributes))
                backgrounds.append(.full(DiffPalette.hunkBackground(for: appearance)))

            case let .pair(left, right, leftLine, rightLine):
                let style = sideBySideParagraphStyle(tabLocation: tabLocation)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: style
                ]
                let rowStart = result.length
                result.append(NSAttributedString(string: left + "\t" + separator + right + "\n", attributes: attributes))

                if let leftLine {
                    applyPrefixStyle(
                        to: result,
                        line: leftLine,
                        at: rowStart,
                        numberWidth: numberWidth,
                        showsNumbers: configuration.showsLineNumbers,
                        prefixWidth: prefixWidth
                    )
                    applyCodeStyle(
                        to: result,
                        line: leftLine,
                        at: rowStart + prefixWidth,
                        configuration: configuration,
                        spans: row.leftSpans,
                        isAddition: false
                    )
                }
                if let rightLine {
                    let rightStart = rowStart + (left as NSString).length + 1 + (separator as NSString).length
                    applyPrefixStyle(
                        to: result,
                        line: rightLine,
                        at: rightStart,
                        numberWidth: numberWidth,
                        showsNumbers: configuration.showsLineNumbers,
                        prefixWidth: prefixWidth
                    )
                    applyCodeStyle(
                        to: result,
                        line: rightLine,
                        at: rightStart + prefixWidth,
                        configuration: configuration,
                        spans: row.rightSpans,
                        isAddition: true
                    )
                }

                let splitX = textContainerInset + tabLocation
                backgrounds.append(.sideBySide(
                    left: leftLine.flatMap { backgroundColor(for: $0.kind, appearance: appearance) },
                    right: rightLine.flatMap { backgroundColor(for: $0.kind, appearance: appearance) },
                    splitX: splitX
                ))

            case let .unknown(text):
                let attributes = DiffTextStyle.lineAttributes(
                    fontSize: configuration.fontSize,
                    appearance: appearance
                )
                result.append(NSAttributedString(string: text + "\n", attributes: attributes))
                backgrounds.append(.full(DiffPalette.unknownBackground(for: appearance)))
            }
        }

        return DiffTextContent(
            attributed: result,
            rowStarts: starts,
            backgrounds: backgrounds,
            hunkRowIndices: hunkRowIndices,
            contentWidth: contentWidth
        )
    }

    private static let textContainerInset: CGFloat = 10

    private static func numberWidth(for file: DiffFile) -> Int {
        let maximum = file.hunks.reduce(1) { current, hunk in
            max(
                current,
                hunk.oldStart + hunk.oldLines,
                hunk.newStart + hunk.newLines
            )
        }
        return max(3, String(maximum).count)
    }

    private static func prefix(
        for line: DiffLine,
        width: Int,
        showsNumbers: Bool
    ) -> String {
        let marker: String
        switch line.kind {
        case .addition: marker = "+"
        case .deletion: marker = "−"
        case .context: marker = " "
        case .unknown: marker = "?"
        }
        guard showsNumbers else { return marker + " " }
        let number = line.oldLineNumber ?? line.newLineNumber
        let numberText = number.map { String($0) } ?? ""
        let padding = String(repeating: " ", count: max(0, width - numberText.count))
        return marker + " " + padding + numberText + " "
    }

    private static func sideBySideParagraphStyle(tabLocation: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1
        style.paragraphSpacing = 0
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        style.tabStops = [
            NSTextTab(textAlignment: .left, location: tabLocation, options: [:])
        ]
        style.defaultTabInterval = tabLocation
        return style
    }

    private static func applyPrefixStyle(
        to string: NSMutableAttributedString,
        line: DiffLine,
        at offset: Int,
        numberWidth: Int,
        showsNumbers: Bool,
        prefixWidth: Int
    ) {
        let length = prefixWidth
        let range = NSRange(location: offset, length: length)
        guard NSMaxRange(range) <= string.length else { return }
        string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        string.addAttribute(
            .foregroundColor,
            value: DiffPalette.markerColor(for: line.kind),
            range: NSRange(location: offset, length: 1)
        )
    }

    private static func applyCodeStyle(
        to string: NSMutableAttributedString,
        line: DiffLine,
        at offset: Int,
        configuration: DiffUIConfiguration,
        spans: [DiffTextSpan],
        isAddition: Bool
    ) {
        let codeLength = (line.text as NSString).length
        let codeRange = NSRange(location: offset, length: codeLength)
        guard NSMaxRange(codeRange) <= string.length else { return }

        if configuration.showsSyntaxHighlighting {
            for token in SwiftSyntaxHighlighter.tokens(in: line.text) {
                let range = NSRange(location: offset + token.span.location, length: token.span.length)
                guard NSMaxRange(range) <= string.length else { continue }
                string.addAttribute(
                    .foregroundColor,
                    value: DiffPalette.syntaxColor(for: token.kind),
                    range: range
                )
            }
        }
        guard !spans.isEmpty else { return }
        let color = isAddition
            ? DiffPalette.intralineAddition(for: NSApp.effectiveAppearance)
            : DiffPalette.intralineDeletion(for: NSApp.effectiveAppearance)
        for span in spans {
            let range = NSRange(location: offset + span.location, length: span.length)
            guard NSMaxRange(range) <= string.length else { continue }
            string.addAttribute(.backgroundColor, value: color, range: range)
        }
    }

    private static func backgroundColor(for kind: DiffLineKind, appearance: NSAppearance) -> NSColor? {
        switch kind {
        case .addition: DiffPalette.additionBackground(for: appearance)
        case .deletion: DiffPalette.deletionBackground(for: appearance)
        case .unknown: DiffPalette.unknownBackground(for: appearance)
        case .context: nil
        }
    }
}
