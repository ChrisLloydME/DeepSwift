//
//  DiffFile.swift
//  DiffCore
//

import Foundation

/// High-level presentation state derived from the Host fields.
///
/// `before` and `after` are preserved on `DiffFile`, so an added binary file
/// and a modified binary file remain distinguishable even though both use the
/// `.binary` presentation state.
public enum DiffFileState: String, Hashable, Sendable, CaseIterable {
    case modified
    case added
    case deleted
    case binary
    case oversized
    case coarse
    case empty
    case unavailable
}

/// A lossless, Kit-owned representation of one DSH changed file.
///
/// The initializer accepts the Host's authoritative `added`/`deleted` values
/// when available. If they are absent, counts are derived from the structured
/// hunk lines for convenience, but `statisticsAreAuthoritative` records which
/// case applies.
public struct DiffFileSource: Hashable, Sendable {
    public let kind: String
    public let path: String
    public let display: String?
    public let before: Bool?
    public let after: Bool?
    public let hunks: [DiffHunkSource]?
    public let coarse: Bool?
    public let added: Int?
    public let deleted: Int?
    /// Some callers have this flag at summary level rather than on the detail
    /// record. Supplying either source form is supported.
    public let binary: Bool?
    public let oversized: Bool?

    public init(
        kind: String,
        path: String,
        display: String? = nil,
        before: Bool? = nil,
        after: Bool? = nil,
        hunks: [DiffHunkSource]? = nil,
        coarse: Bool? = nil,
        added: Int? = nil,
        deleted: Int? = nil,
        binary: Bool? = nil,
        oversized: Bool? = nil
    ) {
        self.kind = kind
        self.path = path
        self.display = display
        self.before = before
        self.after = after
        self.hunks = hunks
        self.coarse = coarse
        self.added = added
        self.deleted = deleted
        self.binary = binary
        self.oversized = oversized
    }
}

public struct DiffFile: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: String
    public let path: String
    public let display: String
    public let before: Bool?
    public let after: Bool?
    public let hunks: [DiffHunk]
    public let isCoarse: Bool
    public let isBinary: Bool
    public let isOversized: Bool
    public let isUnavailable: Bool
    public let added: Int
    public let deleted: Int
    public let statisticsAreAuthoritative: Bool

    public init(source: DiffFileSource) {
        id = source.path
        kind = source.kind
        path = source.path
        display = source.display?.isEmpty == false ? source.display! : source.path
        before = source.before
        after = source.after
        isCoarse = source.coarse == true
        isBinary = source.binary == true || source.kind.caseInsensitiveCompare("binary") == .orderedSame
        isOversized = source.oversized == true || source.kind.caseInsensitiveCompare("oversized") == .orderedSame
        isUnavailable = source.hunks == nil && !isBinary && !isOversized
        hunks = source.hunks?.enumerated().map { index, hunk in
            DiffHunkParser.parse(hunk, index: index)
        } ?? []

        let derivedAdded = hunks.reduce(0) { $0 + $1.addedCount }
        let derivedDeleted = hunks.reduce(0) { $0 + $1.deletedCount }
        if let added = source.added, let deleted = source.deleted {
            self.added = max(0, added)
            self.deleted = max(0, deleted)
            statisticsAreAuthoritative = true
        } else {
            self.added = max(0, source.added ?? derivedAdded)
            self.deleted = max(0, source.deleted ?? derivedDeleted)
            statisticsAreAuthoritative = false
        }
    }

    /// Convenience initializer for already-parsed, Kit-owned hunks.
    public init(
        kind: String = "text",
        path: String,
        display: String? = nil,
        before: Bool? = nil,
        after: Bool? = nil,
        hunks: [DiffHunk] = [],
        coarse: Bool = false,
        added: Int? = nil,
        deleted: Int? = nil,
        binary: Bool = false,
        oversized: Bool = false,
        unavailable: Bool = false
    ) {
        id = path
        self.kind = kind
        self.path = path
        self.display = display?.isEmpty == false ? display! : path
        self.before = before
        self.after = after
        self.hunks = hunks
        isCoarse = coarse
        isBinary = binary
        isOversized = oversized
        isUnavailable = unavailable
        self.added = max(0, added ?? hunks.reduce(0) { $0 + $1.addedCount })
        self.deleted = max(0, deleted ?? hunks.reduce(0) { $0 + $1.deletedCount })
        statisticsAreAuthoritative = added != nil && deleted != nil
    }

    public var state: DiffFileState {
        if isUnavailable { return .unavailable }
        if isBinary { return .binary }
        if isOversized { return .oversized }
        if before == false { return .added }
        if after == false { return .deleted }
        if isCoarse { return .coarse }
        if hunks.isEmpty { return .empty }
        return .modified
    }

    public var fileExtension: String {
        (path as NSString).pathExtension.lowercased()
    }

    public var addedCount: Int { added }
    public var deletedCount: Int { deleted }
    public var hasTextualHunks: Bool { !hunks.isEmpty }
}

extension DiffFileSource {
    /// DSH's changed-file summary does not carry hunks. This produces a
    /// summary-compatible source with authoritative statistics.
    public init(
        kind: String = "text",
        path: String,
        display: String? = nil,
        before: Bool? = nil,
        after: Bool? = nil,
        added: Int,
        deleted: Int,
        binary: Bool? = nil,
        oversized: Bool? = nil
    ) {
        self.init(
            kind: kind,
            path: path,
            display: display,
            before: before,
            after: after,
            hunks: nil,
            coarse: nil,
            added: added,
            deleted: deleted,
            binary: binary,
            oversized: oversized
        )
    }
}
