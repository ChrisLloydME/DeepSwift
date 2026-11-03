//
//  DeepSwiftApp.swift
//  DeepSwift
//

import AppKit
import SwiftUI

@main
struct DeepSwiftApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 580)
                .task {
                    appDelegate.model = model
                    await model.bootstrap()
                }
        }
        .defaultSize(width: 1_240, height: 820)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    Task { await model.createSession() }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.selectedWorkspace == nil)

                Button("New Workspace…") {
                    model.createWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("Session") {
                Button("Send Message") {
                    Task { await model.sendMessage() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedSessionID == nil || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Stop Generation") {
                    Task { await model.cancelCurrentTurn() }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.selectedSession?.isRunning != true)

                Divider()

                Button("Toggle Inspector") {
                    model.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Refresh Sessions") {
                    Task { await model.refreshSessions() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Search Messages…") {
                    model.showSearch = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        guard let model else { return .terminateNow }
        isTerminating = true
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The bridge also exits on stdin EOF if the asynchronous path did not run.
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}
