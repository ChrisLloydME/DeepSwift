//
//  AgentPresetMenu.swift
//  DeepSwift
//

import SwiftUI

/// Selects an Agent composition before the session's first conversation turn.
/// The Host locks the composition once a turn begins, so the control hides then.
struct AgentPresetMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let roster = model.agentPresetRoster, !roster.presets.isEmpty,
           model.conversation.items.isEmpty,
           model.selectedSession?.isRunning != true {
            Menu {
                ForEach(roster.presets) { preset in
                    Button {
                        Task { await model.setAgentPreset(preset.id) }
                    } label: {
                        if preset.id == currentPreset {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                    .disabled(preset.broken != nil)
                    .help(preset.broken ?? preset.description ?? "")
                }
            } label: {
                Label(currentName, systemImage: "person.crop.rectangle.stack")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Agent preset for this session")
        }
    }

    private var currentPreset: String? {
        model.conversation.header?.agentPreset
            ?? model.agentPresetRoster?.presets.first(where: \.isDefault)?.id
    }

    private var currentName: String {
        guard let currentPreset else { return "Agent" }
        return model.agentPresetRoster?.presets.first(where: { $0.id == currentPreset })?.displayName ?? currentPreset
    }
}
