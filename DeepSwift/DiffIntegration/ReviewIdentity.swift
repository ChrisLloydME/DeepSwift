//
//  ReviewIdentity.swift
//  DeepSwift
//

import Foundation

enum ReviewWindowScene {
    static let identifier = "review"
}

/// Immutable identity for one DSH workspace-changes review.
///
/// The Session ID and event sequence identify the review. The turn is
/// descriptive metadata only and deliberately does not participate in
/// equality, so the same event can never produce two Review windows.
struct ReviewIdentity: Codable, Hashable, Sendable {
    let sessionID: String
    let sequence: Int
    let turn: Int?

    var stableIdentifier: String {
        "\(sessionID)#\(sequence)"
    }

    static func == (lhs: ReviewIdentity, rhs: ReviewIdentity) -> Bool {
        lhs.sessionID == rhs.sessionID && lhs.sequence == rhs.sequence
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sessionID)
        hasher.combine(sequence)
    }
}
