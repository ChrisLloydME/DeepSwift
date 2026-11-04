//
//  DiffUIConfiguration.swift
//  DiffUI
//

import DiffCore
import Foundation

public enum DiffPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case unified
    case sideBySide

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unified: "Unified"
        case .sideBySide: "Side by Side"
        }
    }
}

/// Presentation-only options. None of these values affect the DiffCore model.
public struct DiffUIConfiguration: Hashable, Sendable {
    public var showsLineNumbers: Bool
    public var showsSyntaxHighlighting: Bool
    public var wrapsLines: Bool
    public var fontSize: CGFloat
    public var intraline: IntralineOptions

    public init(
        showsLineNumbers: Bool = true,
        showsSyntaxHighlighting: Bool = true,
        wrapsLines: Bool = false,
        fontSize: CGFloat = 12,
        intraline: IntralineOptions = .default
    ) {
        self.showsLineNumbers = showsLineNumbers
        self.showsSyntaxHighlighting = showsSyntaxHighlighting
        self.wrapsLines = wrapsLines
        self.fontSize = max(9, fontSize)
        self.intraline = intraline
    }

    public static let standard = DiffUIConfiguration()
}

public struct DiffReviewConfiguration: Hashable, Sendable {
    public var defaultMode: DiffPresentationMode
    public var diff: DiffUIConfiguration
    public var showsFileNavigator: Bool

    public init(
        defaultMode: DiffPresentationMode = .unified,
        diff: DiffUIConfiguration = .standard,
        showsFileNavigator: Bool = true
    ) {
        self.defaultMode = defaultMode
        self.diff = diff
        self.showsFileNavigator = showsFileNavigator
    }
}
