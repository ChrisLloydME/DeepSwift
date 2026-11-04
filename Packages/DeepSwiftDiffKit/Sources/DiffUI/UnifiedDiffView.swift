//
//  UnifiedDiffView.swift
//  DiffUI
//

import DiffCore
import SwiftUI

/// Native, selectable Unified Diff content. This is a content view only; it
/// does not create windows or know about DSH sessions.
public struct UnifiedDiffView: View {
    public let file: DiffFile
    public let selectedHunk: Int
    public let configuration: DiffUIConfiguration

    public init(
        file: DiffFile,
        selectedHunk: Int = 0,
        configuration: DiffUIConfiguration = .standard
    ) {
        self.file = file
        self.selectedHunk = max(0, selectedHunk)
        self.configuration = configuration
    }

    public var body: some View {
        Group {
            if file.isBinary || file.isOversized || file.isUnavailable || file.hunks.isEmpty {
                DiffUnavailableState(file: file)
            } else {
                VStack(spacing: 0) {
                    if file.isCoarse {
                        CoarseComparisonBanner()
                    }
                    DiffTextScrollView(
                        file: file,
                        configuration: configuration,
                        selectedHunk: selectedHunk,
                        kind: .unified
                    )
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
