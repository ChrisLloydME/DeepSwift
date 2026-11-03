//
//  BackgroundJobsView.swift
//  DeepSwift
//

import SwiftUI

struct BackgroundJobsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Background Jobs", systemImage: "gearshape.2")
                    .font(.headline)
                Spacer()
                if !model.jobs.isEmpty {
                    Text("\(model.jobs.filter(\.isActive).count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()

            if model.jobs.isEmpty {
                ContentUnavailableView(
                    "No Background Jobs",
                    systemImage: "gearshape.2",
                    description: Text("Jobs started by the Agent in this session appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.jobs) { job in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(job.isActive ? Color.accentColor : Color.secondary)
                            .frame(width: 7, height: 7)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(job.displayLabel)
                                    .font(.headline)
                                Spacer()
                                if let status = job.status {
                                    Text(status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(job.isActive ? .green : .secondary)
                                }
                            }
                            if let progress = job.progress, !progress.isEmpty {
                                Text(progress)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            if let detail = job.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                        }
                        if job.isActive {
                            Button("Stop") {
                                Task { await model.killJob(job) }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
