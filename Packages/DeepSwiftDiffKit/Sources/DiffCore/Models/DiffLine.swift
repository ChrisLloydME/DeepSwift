//
//  DiffLine.swift
//  DiffCore
//
//  A single, already-materialized line in a structured hunk.
//

import Foundation

/// Stable identity for a line within a file. The hunk index and the line's
/// index inside that hunk are deterministic, so rebuilding presentation rows
/// never changes a line's identity.
public struct DiffLineID: Hashable, Sendable, Comparable {
    public let hunk: Int
    public let index: Int

    public init(hunk: Int, index: Int) {
        self.hunk = hunk
        self.index = index
    }

    public static func < (lhs: DiffLineID, rhs: DiffLineID) -> Bool {
        (lhs.hunk, lhs.index) < (rhs.hunk, rhs.index)
    }
}

/// The semantic role of a structured hunk line.
///
/// `unknown` exists so malformed or extension records are preserved instead of
/// being silently dropped. Unknown lines have no reliable line numbers.
public enum DiffLineKind: String, Hashable, Sendable, CaseIterable {
    case context
    case addition
    case deletion
    case unknown
}

public struct DiffLine: Identifiable, Hashable, Sendable {
    public let id: DiffLineID
    public let kind: DiffLineKind
    /// Source text without the unified-diff prefix character.
    public let text: String
    /// One-based original line number when the line exists on the old side.
    public let oldLineNumber: Int?
    /// One-based updated line number when the line exists on the new side.
    public let newLineNumber: Int?

    public init(
        id: DiffLineID,
        kind: DiffLineKind,
        text: String,
        oldLineNumber: Int? = nil,
        newLineNumber: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }

    public var isEmpty: Bool {
        text.isEmpty
    }

    public var isChange: Bool {
        kind == .addition || kind == .deletion
    }
}
