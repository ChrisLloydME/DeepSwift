//
//  ContentView.swift
//  DeepSwift
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
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
                    model.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector (⌥⌘I)")
            }
        }
        .alert("DeepSwift", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $model.showSearch) {
            MessageSearchView()
                .environment(model)
        }
        .sheet(isPresented: $model.showFiles) {
            WorkspaceBrowserView()
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
