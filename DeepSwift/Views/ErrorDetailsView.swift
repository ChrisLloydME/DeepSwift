//
//  ErrorDetailsView.swift
//  DeepSwift
//

import AppKit
import SwiftUI

/// Bounded diagnostics for an error. The details scroll independently; Close
/// and Copy Diagnostics remain outside the scroll view.
struct ErrorDetailsView: View {
    let error: AppErrorPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title)
                        .font(.headline)
                    Text("\(error.code)  ·  \(error.diagnosticID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(error.message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let recovery = error.recovery, !recovery.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What you can do")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(recovery)
                                .font(.callout)
                        }
                    }

                    if let details = error.technicalDetails, !details.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Technical details")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(details)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 10) {
                Text(error.diagnosticID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    copyDiagnostics()
                } label: {
                    Label(copied ? "Copied" : "Copy Diagnostics",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy sanitized diagnostic information")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(minWidth: 420, idealWidth: 620, maxWidth: 680,
               minHeight: 280, idealHeight: 430, maxHeight: 560)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error details")
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(error.diagnosticText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

#if DEBUG
#Preview("Error Details — Long") {
    ErrorDetailsView(
        error: AppErrorPresentationFactory.make(
            title: "The local runtime returned an unreadable response",
            message: "DeepSwift could not decode a response from the local runtime. The configuration payload was omitted from this report.",
            recovery: "Retry the action. If it keeps happening, restart the runtime from Settings > General.",
            code: "bridge/frame-decode",
            action: "read a response from the local runtime",
            details: """
            Code: bridge/frame-decode
            Action: read a response from the local runtime
            Frame bytes: 182430
            Decoder: Unexpected type at providers.opencode-go.models[0].contextWindow

            This synthetic preview demonstrates a bounded, selectable diagnostics
            region. No live configuration, credential reference, or token is
            included. Copy Diagnostics copies this sanitized block only.
            """
        )
    )
}

#Preview("Error Details — Short") {
    ErrorDetailsView(
        error: AppErrorPresentationFactory.make(
            message: "The request could not be completed.",
            recovery: "Try again.",
            code: "app/error",
            action: "complete the request",
            details: "No additional details were retained."
        )
    )
}
#endif
