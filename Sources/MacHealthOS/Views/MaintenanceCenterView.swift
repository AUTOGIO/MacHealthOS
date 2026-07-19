import SwiftUI

struct MaintenanceCenterView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCacheFolderPaths: Set<String> = []
    @State private var pendingAction: MaintenanceActionDefinition?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introSection

                    if !appModel.availableCacheFolders.isEmpty {
                        cacheSelectionSection
                    }

                    ForEach(appModel.maintenanceActionDefinitions) { action in
                        actionCard(action)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Safe Maintenance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 720)
        .sheet(item: $pendingAction) { action in
            MaintenanceConfirmationSheet(
                action: action,
                selectedCacheFolders: selectedCacheFolders,
                commandPreview: appModel.manualCommandPreview(for: action.kind),
                onConfirm: {
                    appModel.performMaintenanceAction(action, selectedCacheFolders: selectedCacheFolders)
                }
            )
        }
        .onDisappear {
            appModel.dismissMaintenanceCenter()
        }
    }

    private var introSection: some View {
        GroupBox("Safety Model") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Every maintenance action is gated behind an explicit confirmation step.")
                Text("This build never removes LaunchAgents automatically, never disables security protections, and never runs sudo automatically.")
                    .foregroundStyle(.secondary)
                Text(appModel.lastStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var cacheSelectionSection: some View {
        GroupBox("User Cache Selection") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select cache subfolders inside `~/Library/Caches` if you want to clear them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(appModel.availableCacheFolders) { folder in
                    Toggle(isOn: binding(for: folder.path)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                    .font(.subheadline.weight(.medium))
                                Text(folder.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(folder.estimatedSizeBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func actionCard(_ action: MaintenanceActionDefinition) -> some View {
        GroupBox(action.title) {
            VStack(alignment: .leading, spacing: 10) {
                labeledLine("What will happen", value: whatWillHappenText(for: action))
                labeledLine("Why recommended", value: action.explanation)
                labeledLine("Risk level", value: action.riskLevel.rawValue)
                labeledLine("Estimated impact", value: action.estimatedImpact)
                labeledLine("Reversibility", value: action.reversibility)

                if let warning = action.warning {
                    labeledLine("Warning", value: warning)
                }

                if action.kind == .clearUserCaches {
                    labeledLine("Selected cache folders", value: selectedCacheFolders.isEmpty ? "None selected" : "\(selectedCacheFolders.count) selected")
                }

                HStack {
                    Spacer()

                    if action.kind == .emptyTrash || action.kind == .clearUserCaches {
                        Button("Continue") {
                            pendingAction = action
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(action.kind == .clearUserCaches && selectedCacheFolders.isEmpty)
                    } else {
                        Button("Continue") {
                            pendingAction = action
                        }
                        .buttonStyle(.bordered)
                        .disabled(action.kind == .clearUserCaches && selectedCacheFolders.isEmpty)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var selectedCacheFolders: [UserCacheFolderSnapshot] {
        appModel.availableCacheFolders.filter { selectedCacheFolderPaths.contains($0.path) }
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedCacheFolderPaths.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectedCacheFolderPaths.insert(path)
                } else {
                    selectedCacheFolderPaths.remove(path)
                }
            }
        )
    }

    private func labeledLine(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func whatWillHappenText(for action: MaintenanceActionDefinition) -> String {
        switch action.kind {
        case .emptyTrash:
            "Items currently inside ~/.Trash will be removed after confirmation."
        case .clearUserCaches:
            "The contents of the selected folders inside ~/Library/Caches will be removed, while the folders themselves stay in place."
        case .openDownloadsFolder:
            "Downloads will open in Finder for manual review."
        case .openLoginItemsSettings:
            "The native Login Items settings page will open in System Settings."
        case .flushDNSCache:
            "The suggested DNS flush command will be copied to the clipboard and Terminal will open. The command is not run automatically."
        case .reindexSpotlight:
            "The suggested Spotlight reindex command will be copied to the clipboard and Terminal will open. The command is not run automatically."
        case .generateMaintenanceReport:
            "The current health report will be written as Markdown and JSON in the local report folder."
        }
    }
}

private struct MaintenanceConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let action: MaintenanceActionDefinition
    let selectedCacheFolders: [UserCacheFolderSnapshot]
    let commandPreview: String?
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.title)
                .font(.title2.weight(.semibold))

            detail("What will happen", text: whatWillHappenText)
            detail("Risk level", text: action.riskLevel.rawValue)
            detail("Estimated impact", text: action.estimatedImpact)
            detail("Reversibility", text: action.reversibility)

            if let warning = action.warning {
                detail("Warning", text: warning)
            }

            if action.kind == .clearUserCaches {
                detail("Selected cache folders", text: selectedCacheFolders.map(\.name).joined(separator: ", "))
            }

            if let commandPreview {
                detail("Prepared command", text: commandPreview, monospaced: true)
            }

            Spacer()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                if action.kind == .emptyTrash || action.kind == .clearUserCaches {
                    Button(confirmButtonTitle) {
                        onConfirm()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(confirmButtonTitle) {
                        onConfirm()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }

    private var confirmButtonTitle: String {
        switch action.kind {
        case .emptyTrash, .clearUserCaches:
            "Confirm Delete"
        case .generateMaintenanceReport:
            "Generate Report"
        default:
            "Continue"
        }
    }

    @ViewBuilder
    private func detail(_ title: String, text: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if monospaced {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            } else {
                Text(text)
            }
        }
    }

    private var whatWillHappenText: String {
        switch action.kind {
        case .emptyTrash:
            "Items currently inside ~/.Trash will be removed after confirmation."
        case .clearUserCaches:
            "The contents of the selected folders inside ~/Library/Caches will be removed, while the folders themselves stay in place."
        case .openDownloadsFolder:
            "Downloads will open in Finder for manual review."
        case .openLoginItemsSettings:
            "The native Login Items settings page will open in System Settings."
        case .flushDNSCache:
            "The suggested DNS flush command will be copied to the clipboard and Terminal will open. The command is not run automatically."
        case .reindexSpotlight:
            "The suggested Spotlight reindex command will be copied to the clipboard and Terminal will open. The command is not run automatically."
        case .generateMaintenanceReport:
            "The current health report will be written as Markdown and JSON in the local report folder."
        }
    }
}
