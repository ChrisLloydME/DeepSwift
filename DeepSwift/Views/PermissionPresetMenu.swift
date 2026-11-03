//
//  PermissionPresetMenu.swift
//  DeepSwift
//

import SwiftUI

/// Native selector for the Host's permission-preset catalog. Switching uses
/// the official `/permission <preset>` command, not a private write path.
struct PermissionPresetMenu: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        if let catalog = model.permissionCatalog, !catalog.options.isEmpty {
            Menu {
                ForEach(catalog.options) { option in
                    Button {
                        Task { await model.setPermissionPreset(option.value) }
                    } label: {
                        if option.value == currentValue {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                    .help(option.description ?? "")
                }
                if let current = currentValue, !catalog.options.contains(where: { $0.value == current }) {
                    Divider()
                    Text("Custom: \(current)")
                }
            } label: {
                if compact {
                    Label(displayName, systemImage: "lock.shield")
                        .labelStyle(.titleAndIcon)
                } else {
                    Label(displayName, systemImage: "lock.shield")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Permission preset for this session")
        }
    }

    private var currentValue: String? {
        model.conversation.permissionPreset ?? model.permissionCatalog?.defaultPreset
    }

    private var displayName: String {
        guard let current = currentValue else { return "Permissions" }
        return model.permissionCatalog?.options.first(where: { $0.value == current })?.name ?? current
    }
}
