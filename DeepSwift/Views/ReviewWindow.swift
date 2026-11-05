//
//  ReviewWindow.swift
//  DeepSwift
//

import DiffCore
import DiffUI
import SwiftUI

/// One independent native Review window. The window receives only a stable
/// identity from the scene; the captured request and all file data remain local
/// to this window.
struct ReviewWindow: View {
    @Environment(AppModel.self) private var appModel
    let identity: ReviewIdentity

    @State private var model: ReviewWindowModel?

    var body: some View {
        Group {
            if let model {
                ReviewWindowContent(model: model)
            } else if appModel.reviewCoordinator.request(for: identity) != nil {
                ProgressView("Preparing Review…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReviewUnavailableView()
            }
        }
        .frame(minWidth: 840, minHeight: 540)
        .task(id: identity) {
            prepareModelIfNeeded()
        }
        .onChange(of: appModel.reviewCoordinator.selectionRevision(for: identity)) {
            guard let model,
                  let selection = appModel.reviewCoordinator.selection(for: identity) else { return }
            model.selectFile(selection)
        }
        .onDisappear {
            model?.releaseResources()
            appModel.reviewCoordinator.release(identity)
        }
    }

    private func prepareModelIfNeeded() {
        guard model == nil,
              let request = appModel.reviewCoordinator.request(for: identity) else { return }
        model = ReviewWindowModel(
            request: request,
            initialFileID: appModel.reviewCoordinator.selection(for: identity),
            mode: appModel.reviewCoordinator.mode(for: identity),
            loader: appModel
        )
    }
}

private struct ReviewWindowContent: View {
    @Environment(AppModel.self) private var appModel
    @Bindable var model: ReviewWindowModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("Changes")
        .navigationSubtitle(Text(
            "\(model.sessionTitle) · Turn \(model.request.summary.turn) · \(model.fileCountText)"
        ))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.selectAdjacentFile(offset: -1)
                } label: {
                    Label("Previous File", systemImage: "chevron.up")
                }
                .disabled((model.selectedFileIndex ?? 0) <= 0)
                .help("Show the previous changed file")
                .accessibilityLabel("Previous changed file")

                Button {
                    model.selectAdjacentFile(offset: 1)
                } label: {
                    Label("Next File", systemImage: "chevron.down")
                }
                .disabled((model.selectedFileIndex ?? -1) >= model.request.summary.files.count - 1)
                .help("Show the next changed file")
                .accessibilityLabel("Next changed file")
            }

            ToolbarItem(placement: .primaryAction) {
                Picker("Diff Presentation", selection: $model.mode) {
                    ForEach(DiffPresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .help("Choose Unified or Side-by-Side Diff")
                .accessibilityLabel("Diff presentation mode")
            }
        }
        .task(id: model.selectedFileID) {
            await model.loadSelectedFile()
        }
        .onChange(of: model.selectedFileID) {
            appModel.reviewCoordinator.setSelection(model.selectedFileID, for: model.identity)
        }
        .onChange(of: model.mode) {
            appModel.reviewCoordinator.setMode(model.mode, for: model.identity)
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section {
                ForEach(Array(model.request.summary.files.enumerated()), id: \.element.path) { index, file in
                    if model.summary.files.indices.contains(index) {
                        DiffFileRow(file: model.summary.files[index])
                            .tag(file.path)
                    }
                }
            } header: {
                Text(model.fileCountText)
            } footer: {
                if let cwd = model.request.summary.cwd, !cwd.isEmpty {
                    Text((cwd as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cwd)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Changed files")
    }

    @ViewBuilder
    private var detail: some View {
        if model.request.summary.files.isEmpty {
            ContentUnavailableView(
                "No Changed Files",
                systemImage: "plus.forwardslash.minus",
                description: Text("This turn did not report any changed files.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let index = model.selectedFileIndex {
            switch model.state(for: index) {
            case .notRequested, .loading:
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading comparison…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading comparison")

            case let .failed(message):
                ReviewComparisonErrorView(message: message) {
                    Task { await model.loadSelectedFile(force: true) }
                }

            case let .loaded(file):
                DiffReviewDetailView(
                    file: file,
                    configuration: .init(),
                    mode: $model.mode
                )
                .id(file.id)
            }
        } else {
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a changed file to review its comparison.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedFileID },
            set: { model.selectFile($0) }
        )
    }
}

private struct ReviewComparisonErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Comparison Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 6) {
                Text(message)
                Text("The DSH Host may no longer retain this comparison. DeepSwift does not recreate it from the current workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Requests this file comparison from the DSH Host again")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReviewUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Review Unavailable", systemImage: "doc.questionmark")
        } description: {
            Text("The captured workspace changes are no longer available. Reopen the Review from the Chat session.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
