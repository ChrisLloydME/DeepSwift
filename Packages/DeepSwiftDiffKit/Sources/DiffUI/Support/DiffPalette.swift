//
//  DiffPalette.swift
//  DiffUI
//

import AppKit
import DiffCore

enum DiffPalette {
    static func codeFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func codeFont(size: CGFloat) -> NSFont {
        codeFont(size: size, weight: .regular)
    }

    static func lineNumberFont(size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: max(9, size - 1), weight: .regular)
    }

    static func additionBackground(for appearance: NSAppearance?) -> NSColor {
        NSColor.systemGreen.withAlphaComponent(isDark(appearance) ? 0.13 : 0.11)
    }

    static func deletionBackground(for appearance: NSAppearance?) -> NSColor {
        NSColor.systemRed.withAlphaComponent(isDark(appearance) ? 0.13 : 0.10)
    }

    static func intralineAddition(for appearance: NSAppearance?) -> NSColor {
        NSColor.systemGreen.withAlphaComponent(isDark(appearance) ? 0.28 : 0.26)
    }

    static func intralineDeletion(for appearance: NSAppearance?) -> NSColor {
        NSColor.systemRed.withAlphaComponent(isDark(appearance) ? 0.28 : 0.24)
    }

    static func hunkBackground(for appearance: NSAppearance?) -> NSColor {
        NSColor.secondaryLabelColor.withAlphaComponent(isDark(appearance) ? 0.10 : 0.07)
    }

    static func unknownBackground(for appearance: NSAppearance?) -> NSColor {
        NSColor.systemOrange.withAlphaComponent(isDark(appearance) ? 0.14 : 0.09)
    }

    static func syntaxColor(for kind: DiffSyntaxTokenKind) -> NSColor {
        switch kind {
        case .keyword: NSColor.systemPink
        case .type: NSColor.systemTeal
        case .string: NSColor.systemRed
        case .comment: NSColor.secondaryLabelColor
        case .number: NSColor.systemBlue
        case .attribute: NSColor.systemOrange
        }
    }

    static func markerColor(for kind: DiffLineKind) -> NSColor {
        switch kind {
        case .addition: NSColor.systemGreen
        case .deletion: NSColor.systemRed
        case .context: NSColor.secondaryLabelColor
        case .unknown: NSColor.systemOrange
        }
    }

    private static func isDark(_ appearance: NSAppearance?) -> Bool {
        let match = appearance?.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }
}

enum DiffTextStyle {
    static func paragraphStyle(
        fontSize: CGFloat,
        tabLocation: CGFloat? = nil,
        isHeader: Bool = false
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = isHeader ? 8 : 0
        style.headIndent = 8
        style.firstLineHeadIndent = 8
        style.tailIndent = -8
        if let tabLocation {
            style.tabStops = [
                NSTextTab(textAlignment: .left, location: tabLocation, options: [:])
            ]
            style.defaultTabInterval = tabLocation
        }
        return style
    }

    static func lineAttributes(
        fontSize: CGFloat,
        appearance: NSAppearance?,
        isHeader: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: isHeader
                ? DiffPalette.codeFont(size: max(9, fontSize - 1), weight: .medium)
                : DiffPalette.codeFont(size: fontSize),
            .foregroundColor: isHeader ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraphStyle(fontSize: fontSize, isHeader: isHeader)
        ]
    }
}
