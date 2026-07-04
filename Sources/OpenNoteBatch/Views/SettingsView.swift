import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Form {
            Section("Microsoft Graph") {
                TextField("Client ID", text: $model.settings.clientID)
                TextField("Redirect URI", text: $model.settings.redirectURI)
                TextField("Tenant override", text: $model.settings.tenantOverride)
            }

            Section("Permissions") {
                Picker("Preset", selection: $model.settings.permissionPreset) {
                    ForEach(PermissionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Requested scopes") {
                    Text(model.settings.permissionPreset.scopes.joined(separator: " "))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                Text("Register \(model.settings.redirectURI) as a mobile/desktop redirect URI in Microsoft Entra. Full batch mode asks for powerful permissions; exporter mode is smaller and better for attachment-only workflows.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 680)
    }
}
