//
//  ContentView.swift
//  DeepSwift
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 380)
        } detail: {
            Group {
                if case let .failed(message) = model.connectionState {
                    RuntimeFailureView(message: message)
                } else if model.selectedSessionID != nil {
                    ChatView()
                } else {
                    WelcomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            // Attach the inspector to the detail column, not to the
            // NavigationSplitView. The detail column owns the trailing
            // presentation; the split view owns only the leading sidebar.
            .inspector(isPresented: $model.showInspector) {
                InspectorView()
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        // The inspector column is already full height. Removing the opaque
        // window-toolbar background lets its native glass material continue
        // behind the toolbar instead of showing a white titlebar strip.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.createSession() }
                } label: {
                    Label("New Session", systemImage: "square.and.pencil")
                }
                .help("New Session (⌘N)")
                .disabled(model.selectedWorkspace == nil)

                Button {
                    model.createWorkspace()
                } label: {
                    Label("New Workspace", systemImage: "folder.badge.plus")
                }
                .help("New Workspace (⇧⌘N)")

                Button {
                    model.showSearch = true
                } label: {
                    Label("Search Messages", systemImage: "magnifyingglass")
                }
                .help("Search Messages (⇧⌘F)")

                Button {
                    model.showFiles = true
                } label: {
                    Label("Workspace Files", systemImage: "folder")
                }
                .help("Browse Workspace Files")
                .disabled(model.selectedSessionID == nil)

                Button {
                    guard let context = model.changesContext else { return }
                    let identity = model.registerReview(for: context)
                    openWindow(id: ReviewWindowScene.identifier, value: identity)
                } label: {
                    Label("Changes", systemImage: "plus.forwardslash.minus")
                }
                .help("Review Changed Files (⇧⌘D)")
                .disabled(model.changesContext == nil)

                Button {
                    model.showTerminal = true
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .help("Open Terminal (⇧⌘T)")
                .disabled(model.selectedSessionID == nil)

                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector (⌥⌘I)")
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.isFileURL {
                Task { await model.openReferencedPath(url.path) }
                return .handled
            }
            if url.scheme == "dsh-file" {
                Task { await model.openReferencedPath(MarkdownRouting.workspacePath(from: url)) }
                return .handled
            }
            if url.scheme == nil {
                Task { await model.openReferencedPath(url.relativeString) }
                return .handled
            }
            return .systemAction
        })
        .alert(item: Binding(
            get: { model.errorPresentation },
            set: { if $0 == nil { model.clearError() } }
        )) { error in
            if error.hasDetails {
                Alert(
                    title: Text(error.title),
                    message: Text(error.alertMessage),
                    primaryButton: .default(Text("Details")) {
                        Task { @MainActor in
                            model.clearError()
                            // Let the alert finish dismissing before the
                            // details sheet takes over the same presentation.
                            try? await Task.sleep(for: .milliseconds(200))
                            model.errorDetails = error
                        }
                    },
                    secondaryButton: .cancel(Text("OK")) {
                        model.clearError()
                    }
                )
            } else {
                Alert(
                    title: Text(error.title),
                    message: Text(error.alertMessage),
                    dismissButton: .default(Text("OK")) {
                        model.clearError()
                    }
                )
            }
        }
        .sheet(item: $model.errorDetails) { error in
            ErrorDetailsView(error: error)
                .environment(model)
        }
        .sheet(isPresented: $model.showSearch) {
            MessageSearchView()
                .environment(model)
        }
        .sheet(isPresented: $model.showFiles) {
            WorkspaceBrowserView()
                .environment(model)
        }
        .sheet(isPresented: $model.showTerminal) {
            TerminalWorkspaceView()
                .environment(model)
        }
        .sheet(isPresented: $model.showJobs) {
            BackgroundJobsView()
                .environment(model)
        }
        .sheet(item: Binding(
            get: { model.pendingApprovals.first },
            set: { _ in }
        )) { approval in
            ApprovalRequestView(approval: approval)
                .environment(model)
        }
        .sheet(item: Binding(
            get: { model.pendingQuestions.first },
            set: { _ in }
        )) { question in
            QuestionRequestView(question: question)
                .environment(model)
        }
    }
}

struct RuntimeFailureView: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Runtime Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await model.restartRuntime() }
            }
            .buttonStyle(.borderedProminent)

            SettingsLink {
                Text("Runtime Settings…")
            }
            .buttonStyle(.bordered)

            if let detail = model.lastRuntimeError, !detail.isEmpty {
                DisclosureGroup("Diagnostics") {
                    ScrollView {
                        Text(detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
    }
}
