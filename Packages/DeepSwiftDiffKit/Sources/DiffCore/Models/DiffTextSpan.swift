//
//  DiffTextSpan.swift
//  DiffCore
//

import Foundation

/// A UTF-16 range, matching the coordinate space used by Foundation and
/// AppKit attributed strings. Keeping this type in DiffCore avoids importing
/// AppKit and makes the ranges easy to test independently of rendering.
public struct DiffTextSpan: Hashable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public var isEmpty: Bool {
        length == 0
    }

    public var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}
