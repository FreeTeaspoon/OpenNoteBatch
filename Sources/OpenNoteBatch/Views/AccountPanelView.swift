import SwiftUI

struct AccountPanelView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Form {
            Section("Current Account") {
                if let account = model.auth.account {
                    LabeledContent("Name", value: account.displayName)
                    LabeledContent("Email", value: account.email)
                    LabeledContent("Account type", value: account.accountKind.title)

                    Button {
                        model.auth.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sign In") {
                ForEach(AccountKind.allCases) { kind in
                    Button {
                        model.signIn(kind: kind)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(kind.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: kind.symbol)
                        }
                    }
                }
            }

            Section("Permissions") {
                LabeledContent("Preset", value: model.settings.permissionPreset.title)
                Text(model.settings.permissionPreset.scopes.joined(separator: " "))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}
