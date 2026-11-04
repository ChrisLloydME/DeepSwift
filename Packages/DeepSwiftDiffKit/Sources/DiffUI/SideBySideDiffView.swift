//
//  SideBySideDiffView.swift
//  DiffUI
//

import DiffCore
import SwiftUI

/// Native two-column Diff content. The columns are aligned in one selectable
/// text surface so resizing and vertical scrolling cannot drift apart.
public struct SideBySideDiffView: View {
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
                        kind: .sideBySide
                    )
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


}
