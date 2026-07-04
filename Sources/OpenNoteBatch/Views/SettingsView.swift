import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("OpenNote Batch Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Form {
                TextField("Microsoft client ID", text: $model.settings.clientID)
                TextField("Redirect URI", text: $model.settings.redirectURI)
                TextField("Tenant override", text: $model.settings.tenantOverride)
                Picker("Permission preset", selection: $model.settings.permissionPreset) {
                    ForEach(PermissionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Requested Scopes")
                    .font(.headline)
                Text(model.settings.permissionPreset.scopes.joined(separator: " "))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Register `\(model.settings.redirectURI)` as a mobile/desktop redirect URI in Microsoft Entra. Full batch mode asks for powerful permissions; exporter mode is smaller and better for attachment-only workflows.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 640)
    }
}

