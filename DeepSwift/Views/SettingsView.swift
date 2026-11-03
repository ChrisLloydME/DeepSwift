//
//  SettingsView.swift
//  DeepSwift
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RuntimeSettingsView()
                .tabItem { Label("Runtime", systemImage: "server.rack") }
            ModelSettingsView()
                .tabItem { Label("Models", systemImage: "cpu") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 430)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("sendOnEnter") private var sendOnEnter = true
    @AppStorage("showTimestamps") private var showTimestamps = false
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section("Composer") {
                Toggle("Send with Return", isOn: $sendOnEnter)
                Text(sendOnEnter
                     ? "Return sends; Shift-Return inserts a newline."
                     : "Return inserts a newline; Command-Return sends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Conversation") {
                Toggle("Show message timestamps", isOn: $showTimestamps)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct RuntimeSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("nodePathOverride") private var nodePath = ""
    @AppStorage("dshHomeOverride") private var dshHome = ""
    @AppStorage("allowProviderEnv") private var allowProviderEnv = false
    @State private var isRestarting = false

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Connection", value: model.connectionState.label)
                if let version = model.runtimeFacts?.dshVersion ?? model.runtimeConfiguration?.dshVersion {
                    LabeledContent("DSH version", value: version)
                }
                if let nodeVersion = model.runtimeFacts?.nodeVersion {
                    LabeledContent("Node version", value: nodeVersion)
                }
                if let pid = model.runtimeFacts?.hostPid {
                    LabeledContent("Host PID", value: "\(pid)")
                }
            }

            Section("Paths") {
                TextField("Node executable", text: $nodePath, prompt: Text("/opt/homebrew/bin/node"))
                TextField("Isolated DSH home", text: $dshHome, prompt: Text("Application Support/DeepSwift/DSHHome"))
                if let configuration = model.runtimeConfiguration {
                    LabeledContent("Runtime") {
                        Text(configuration.dshBinPath)
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Profile") {
                        Text((configuration.dshHome as NSString).abbreviatingWithTildeInPath)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                Text("Overrides apply to the next runtime start. The app refuses to use your existing ~/.dsh profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Credentials") {
                Toggle("Pass provider API key environment variables", isOn: $allowProviderEnv)
                Text("When enabled, DEEPSEEK_API_KEY, OPENAI_API_KEY, and ANTHROPIC_API_KEY from the app environment are passed to the isolated Host. The app never stores credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Restart Runtime") {
                        restart()
                    }
                    .disabled(isRestarting)
                    Button("Reveal Profile Folder") {
                        model.revealRuntimeLog()
                    }
                    if isRestarting {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func restart() {
        isRestarting = true
        Task {
            await model.restartRuntime()
            isRestarting = false
        }
    }
}

private struct ModelSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("DeepSeek Account") {
                if let account = model.account {
                    LabeledContent("Status") {
                        Text(account.isSignedIn ? "Signed in" : "Signed out")
                            .foregroundStyle(account.isSignedIn ? .green : .secondary)
                    }
                    if let attempt = account.attempt, !account.isSignedIn {
                        LabeledContent("Sign-in") {
                            Text(attempt.phase.replacingOccurrences(of: "-", with: " ").capitalized)
                                .foregroundStyle(.secondary)
                        }
                        if let error = attempt.errorCode {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    LabeledContent("Status", value: "Unknown")
                }

                if model.isSigningIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for browser sign-in…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            Task { await model.cancelSignIn() }
                        }
                    }
                } else if model.account?.isSignedIn == true {
                    HStack {
                        Button("Sign Out") {
                            Task { await model.signOut() }
                        }
                        Spacer()
                        Button("Refresh") {
                            Task { await model.refreshAccount() }
                        }
                    }
                } else {
                    HStack {
                        Button("Sign In with Browser") {
                            Task { await model.beginSignIn() }
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                        Button("Refresh") {
                            Task { await model.refreshAccount() }
                        }
                    }
                    Text("Sign-in opens the system browser and stores credentials only in the isolated DSH profile. DeepSwift never receives or stores the token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let models = model.models, !models.isEmpty {
                Section("Available Models") {
                    ForEach(models.groups) { group in
                        ForEach(group.models) { entry in
                            LabeledContent(entry.displayName) {
                                Text("\(group.id)/\(entry.id)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                if let failures = models.failures, !failures.isEmpty {
                    Section("Provider Issues") {
                        ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                            Label(failure.message ?? "Unavailable", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Models Available",
                        systemImage: "cpu",
                        description: Text("Authenticate the isolated DSH profile. Credentials and provider configuration stay in DSH; DeepSwift does not keep its own credential store.")
                    )
                    Button("Refresh Catalog") {
                        Task { await model.refreshModels() }
                    }
                }
            }

            Section("Defaults") {
                if let selected = model.models?.defaultSelection {
                    LabeledContent("Default", value: "\(selected.provider)/\(selected.model)")
                } else {
                    Text("No default model is recorded by the Host.")
                        .foregroundStyle(.secondary)
                }
                Button("Refresh Catalog") {
                    Task { await model.refreshModels() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AboutSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showLicenses = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                Text("DeepSwift")
                    .font(.title2.weight(.semibold))
                Text("Native macOS client for DeepSeek Harness")
                    .foregroundStyle(.secondary)

                Form {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("DSH", value: model.runtimeFacts?.dshVersion ?? model.runtimeConfiguration?.dshVersion ?? "Unknown")
                    LabeledContent("Protocol", value: "\(BridgeProtocol.version)")
                    LabeledContent("Runtime home") {
                        Text((model.runtimeConfiguration?.dshHome as NSString?)?.abbreviatingWithTildeInPath ?? "—")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .formStyle(.grouped)

                VStack(spacing: 6) {
                    Text("DSH is licensed under the MIT License.")
                    Text("The application bundles or launches unmodified official DSH packages. Third-party notices are included in Docs/third-party-notices.md.")
                        .multilineTextAlignment(.center)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                if let url = URL(string: "https://github.com/deepseek-ai/deepseek-harness") {
                    Link("DeepSeek Harness on GitHub", destination: url)
                }
                if let url = URL(string: "https://github.com/deepseek-ai/deepseek-harness/blob/main/LICENSE") {
                    Link("MIT License", destination: url)
                }
                Button("Third-Party Licenses") {
                    showLicenses = true
                }
                .buttonStyle(.link)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showLicenses) {
            LicensesView()
        }
    }
}

private struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Third-Party Licenses")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DeepSeek Harness").font(.headline)
                    Text("Copyright (c) 2026 DeepSeek — MIT License")
                        .font(.callout)
                    Text("""
                    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

                    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                    """)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    Divider()
                    Text("DeepSwift uses Apple SwiftUI, AppKit, and Foundation. It does not bundle third-party Swift packages in this build. Node.js is used from the host machine in development; a packaged build must include Node's license and bundled notices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620, height: 520)
    }
}
