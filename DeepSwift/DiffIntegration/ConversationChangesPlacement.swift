//
//  ConversationChangesPlacement.swift
//  DeepSwift
//

import Foundation

/// Pure placement rules for the compact changed-files summary.
enum ConversationChangesPlacement {
    /// A changes snapshot is only visible in the Session it was captured for.
    static func visibleContext(
        _ context: WorkspaceChangesContext?,
        sessionID: String?
    ) -> WorkspaceChangesContext? {
        guard let context, context.sessionID == sessionID else { return nil }
        return context
    }

    /// Splits the transcript at the durable workspace-changes event sequence.
    /// Items after the anchor stay below the summary, so an older changes event
    /// is never shown as though it belonged to a newer turn.
    static func split(
        _ items: [ChatItem],
        at sequence: Int?
    ) -> (before: [ChatItem], after: [ChatItem]) {
        guard let sequence else { return (items, []) }
        return (
            items.filter { $0.seq < sequence },
            items.filter { $0.seq >= sequence }
        )
    }
}
