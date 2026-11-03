//
//  WelcomeView.swift
//  DeepSwift
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("DeepSwift")
                    .font(.system(size: 30, weight: .semibold))
                Text("A native macOS client for DeepSeek Harness.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if model.workspaces.isEmpty {
                VStack(spacing: 12) {
                    Text("Choose a workspace folder to begin. DSH remains the source of truth for sessions, files, and agent activity.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 430)
                    Button {
                        model.createWorkspace()
                    } label: {
                        Label("Choose Workspace…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        Task { await model.createSession() }
                    } label: {
                        Label("New Session", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.selectedWorkspace == nil)

                    Button {
                        model.createWorkspace()
                    } label: {
                        Label("Open Workspace…", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            if let workspace = model.selectedWorkspace {
                Label(workspace.abbreviatedPath, systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            HStack(spacing: 18) {
                Label(runtimeLabel, systemImage: runtimeSymbol)
                if let version = model.runtimeFacts?.dshVersion {
                    Label("DSH \(version)", systemImage: "shippingbox")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var runtimeLabel: String {
        switch model.connectionState {
        case .ready: return "Runtime ready"
        case .starting: return "Starting runtime"
        case .degraded: return "Reconnecting"
        case .failed: return "Runtime unavailable"
        case .idle: return "Not connected"
        }
    }

    private var runtimeSymbol: String {
        switch model.connectionState {
        case .ready: return "checkmark.circle"
        case .starting, .degraded: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        case .idle: return "circle.dashed"
        }
    }
}
