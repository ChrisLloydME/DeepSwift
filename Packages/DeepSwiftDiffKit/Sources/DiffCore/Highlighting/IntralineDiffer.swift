//
//  IntralineDiffer.swift
//  DiffCore
//

import Foundation

public struct IntralineOptions: Hashable, Sendable {
    /// Lines longer than this are displayed without intraline highlighting.
    public var maxLineLength: Int
    /// Limits expensive work when a hunk contains many replacements.
    public var maxPairsPerHunk: Int
    public var isEnabled: Bool

    public init(
        maxLineLength: Int = 4_096,
        maxPairsPerHunk: Int = 200,
        isEnabled: Bool = true
    ) {
        self.maxLineLength = max(64, maxLineLength)
        self.maxPairsPerHunk = max(1, maxPairsPerHunk)
        self.isEnabled = isEnabled
    }

    public static let `default` = IntralineOptions()
    public static let disabled = IntralineOptions(isEnabled: false)
}

public struct IntralineResult: Hashable, Sendable {
    public let oldSpans: [DiffTextSpan]
    public let newSpans: [DiffTextSpan]

    public init(oldSpans: [DiffTextSpan], newSpans: [DiffTextSpan]) {
        self.oldSpans = oldSpans
        self.newSpans = newSpans
    }

    public var isEmpty: Bool {
        oldSpans.isEmpty && newSpans.isEmpty
    }
}

/// A small, deterministic character-level differ for paired replacement lines.
///
/// It compares complete `Character` values and reports UTF-16 ranges, so
/// grapheme clusters and supplementary Unicode scalars are not split. The
/// common-prefix/common-suffix scan is linear; there is no full edit-distance
/// matrix. Long lines and excessive replacement pairs are skipped.
public enum IntralineDiffer {
    public static func compare(
        old: String,
        new: String,
        options: IntralineOptions = .default
    ) -> IntralineResult {
        guard options.isEnabled else {
            return IntralineResult(oldSpans: [], newSpans: [])
        }

        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        guard oldCharacters.count <= options.maxLineLength,
              newCharacters.count <= options.maxLineLength else {
            return IntralineResult(oldSpans: [], newSpans: [])
        }

        let oldCount = oldCharacters.count
        let newCount = newCharacters.count
        let minimumCount = min(oldCount, newCount)

        var prefix = 0
        while prefix < minimumCount, oldCharacters[prefix] == newCharacters[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < minimumCount - prefix,
              oldCharacters[oldCount - 1 - suffix] == newCharacters[newCount - 1 - suffix] {
            suffix += 1
        }

        let oldRange = prefix..<(oldCount - suffix)
        let newRange = prefix..<(newCount - suffix)
        guard !oldRange.isEmpty || !newRange.isEmpty else {
            return IntralineResult(oldSpans: [], newSpans: [])
        }

        let oldOffsets = utf16Offsets(for: oldCharacters)
        let newOffsets = utf16Offsets(for: newCharacters)
        let oldSpan = DiffTextSpan(
            location: oldOffsets[oldRange.lowerBound],
            length: oldOffsets[oldRange.upperBound] - oldOffsets[oldRange.lowerBound]
        )
        let newSpan = DiffTextSpan(
            location: newOffsets[newRange.lowerBound],
            length: newOffsets[newRange.upperBound] - newOffsets[newRange.lowerBound]
        )

        return IntralineResult(
            oldSpans: oldSpan.isEmpty ? [] : [oldSpan],
            newSpans: newSpan.isEmpty ? [] : [newSpan]
        )
    }

    /// Computes intraline spans for adjacent deletion/addition runs in one
    /// hunk. Only replacement groups are paired; unrelated groups are left
    /// alone. The returned dictionary is keyed by stable line identity.
    public static func spansByLineID(
        in hunk: DiffHunk,
        options: IntralineOptions = .default
    ) -> [DiffLineID: [DiffTextSpan]] {
        guard options.isEnabled else { return [:] }
        var result: [DiffLineID: [DiffTextSpan]] = [:]
        var pairCount = 0

        var index = 0
        while index < hunk.lines.count {
            let kind = hunk.lines[index].kind
            guard kind == .deletion || kind == .addition else {
                index += 1
                continue
            }

            var deletions: [DiffLine] = []
            var additions: [DiffLine] = []
            while index < hunk.lines.count {
                let line = hunk.lines[index]
                switch line.kind {
                case .deletion:
                    deletions.append(line)
                case .addition:
                    additions.append(line)
                case .context, .unknown:
                    break
                }
                if line.kind == .context || line.kind == .unknown {
                    break
                }
                index += 1
            }

            let pairTotal = min(deletions.count, additions.count)
            for pairIndex in 0..<pairTotal {
                guard pairCount < options.maxPairsPerHunk else { break }
                pairCount += 1
                let deletion = deletions[pairIndex]
                let addition = additions[pairIndex]
                let comparison = compare(old: deletion.text, new: addition.text, options: options)
                if !comparison.oldSpans.isEmpty {
                    result[deletion.id] = comparison.oldSpans
                }
                if !comparison.newSpans.isEmpty {
                    result[addition.id] = comparison.newSpans
                }
            }
        }

        return result
    }

    private static func utf16Offsets(for characters: [Character]) -> [Int] {
        var offsets = [0]
        offsets.reserveCapacity(characters.count + 1)
        var offset = 0
        for character in characters {
            offset += character.utf16.count
            offsets.append(offset)
        }
        return offsets
    }
}
