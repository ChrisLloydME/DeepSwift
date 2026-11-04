//
//  DiffHunk.swift
//  DiffCore
//

import Foundation

/// The structured hunk shape returned by DSH. It intentionally contains the
/// original line-prefixed records; `DiffHunkParser` turns it into typed lines.
public struct DiffHunkSource: Hashable, Sendable {
    public let oldStart: Int
    public let oldLines: Int
    public let newStart: Int
    public let newLines: Int
    public let lines: [String]

    public init(
        oldStart: Int,
        oldLines: Int,
        newStart: Int,
        newLines: Int,
        lines: [String]
    ) {
        self.oldStart = oldStart
        self.oldLines = oldLines
        self.newStart = newStart
        self.newLines = newLines
        self.lines = lines
    }
}

public struct DiffHunk: Identifiable, Hashable, Sendable {
    public let id: Int
    public let oldStart: Int
    public let oldLines: Int
    public let newStart: Int
    public let newLines: Int
    public let lines: [DiffLine]

    public init(
        id: Int,
        oldStart: Int,
        oldLines: Int,
        newStart: Int,
        newLines: Int,
        lines: [DiffLine]
    ) {
        self.id = id
        self.oldStart = oldStart
        self.oldLines = oldLines
        self.newStart = newStart
        self.newLines = newLines
        self.lines = lines
    }

    /// Standard unified hunk header, including exact Host-provided counts.
    public var header: String {
        "@@ -\(oldStart),\(oldLines) +\(newStart),\(newLines) @@"
    }

    public var addedCount: Int {
        lines.lazy.filter { $0.kind == .addition }.count
    }

    public var deletedCount: Int {
        lines.lazy.filter { $0.kind == .deletion }.count
    }

    public var hasChanges: Bool {
        lines.contains(where: \.isChange)
    }
}
