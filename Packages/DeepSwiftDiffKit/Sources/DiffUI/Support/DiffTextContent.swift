//
//  DiffTextContent.swift
//  DiffUI
//

import AppKit
import DiffCore

struct DiffRowBackground {
    let left: NSColor?
    let right: NSColor?
    let splitX: CGFloat?

    static let none = DiffRowBackground(left: nil, right: nil, splitX: nil)

    static func full(_ color: NSColor?) -> DiffRowBackground {
        DiffRowBackground(left: color, right: nil, splitX: nil)
    }

    static func sideBySide(left: NSColor?, right: NSColor?, splitX: CGFloat) -> DiffRowBackground {
        DiffRowBackground(left: left, right: right, splitX: splitX)
    }
}

struct DiffTextContent {
    let attributed: NSAttributedString
    let rowStarts: [Int]
    let backgrounds: [DiffRowBackground]
    let hunkRowIndices: [Int: Int]
    let contentWidth: CGFloat

    var isEmpty: Bool { attributed.length == 0 }
}

/// NSTextView subclass that paints full-width row backgrounds before AppKit
/// draws the text and selection. Text attributes alone only paint the glyph
/// bounds, which looks cramped in a diff.
final class DiffTextView: NSTextView {

    var rowStarts: [Int] = []
    var rowBackgrounds: [DiffRowBackground] = []
    var splitX: CGFloat?

    override func drawBackground(in rect: NSRect) {
        drawDiffRowBackgrounds(in: rect)
        super.drawBackground(in: rect)
    }

    private func drawDiffRowBackgrounds(in dirtyRect: NSRect) {
        guard let layoutManager, let textContainer, textStorage?.length ?? 0 > 0 else { return }
        let glyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        guard characterRange.length > 0 else { return }

        let firstRow = rowIndex(atOrBefore: characterRange.location)
        guard firstRow < rowStarts.count else { return }
        let textLength = textStorage?.length ?? 0
        let fullWidth = max(bounds.width, enclosingScrollView?.contentSize.width ?? bounds.width)

        var row = max(0, firstRow)
        while row < rowStarts.count {
            let start = rowStarts[row]
            if start > NSMaxRange(characterRange) { break }
            defer { row += 1 }
            guard start < textLength else { continue }
            let background = rowBackgrounds.indices.contains(row) ? rowBackgrounds[row] : .none
            guard background.left != nil || background.right != nil else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: start)
            let rowEnd = row + 1 < rowStarts.count ? rowStarts[row + 1] : textLength
            let rowCharacterRange = NSRange(
                location: start,
                length: max(0, rowEnd - start)
            )
            let rowGlyphRange = layoutManager.glyphRange(
                forCharacterRange: rowCharacterRange,
                actualCharacterRange: nil
            )
            var lineRect = layoutManager.boundingRect(
                forGlyphRange: rowGlyphRange,
                in: textContainer
            )
            if lineRect.height <= 0 {
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            lineRect.origin.y += textContainerInset.height
            lineRect.origin.x = 0
            lineRect.size.width = fullWidth
            guard lineRect.intersects(dirtyRect) else { continue }

            if let splitX = background.splitX {
                if let left = background.left {
                    left.setFill()
                    NSRect(
                        x: lineRect.minX,
                        y: lineRect.minY,
                        width: min(splitX, fullWidth),
                        height: lineRect.height
                    ).fill()
                }
                if let right = background.right, splitX < fullWidth {
                    right.setFill()
                    NSRect(
                        x: splitX,
                        y: lineRect.minY,
                        width: fullWidth - splitX,
                        height: lineRect.height
                    ).fill()
                }
            } else if let left = background.left {
                left.setFill()
                lineRect.fill()
            } else if let right = background.right {
                right.setFill()
                lineRect.fill()
            }
        }
    }

    private func rowIndex(atOrBefore location: Int) -> Int {
        guard !rowStarts.isEmpty else { return 0 }
        var low = 0
        var high = rowStarts.count
        while low < high {
            let mid = (low + high) / 2
            if rowStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }
}
