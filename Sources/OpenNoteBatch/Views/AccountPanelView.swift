import SwiftUI

struct AccountPanelView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let account = model.auth.account {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Logged in Microsoft Account")
                            .font(.title2.weight(.semibold))
                        Text(account.email)
                            .foregroundStyle(.secondary)
                        Text(account.accountKind.title)
                            .font(.headline)
                    }
                    Spacer()
                    Button("Re Login") {
                        model.auth.signOut()
                    }
                }
            } else {
                Text("Choose an account type to sign in.")
                    .font(.title3.weight(.semibold))
            }

            LazyVGrid(columns: [.init(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(AccountKind.allCases) { kind in
                    Button {
                        model.signIn(kind: kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 26, weight: .semibold))
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.title)
                                    .font(.headline)
                                Text(kind.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Upload and import limits are enforced by Microsoft Graph and your account type. This app keeps broad permissions visible in Settings so you can choose exporter-only or full batch access.")
                .foregroundStyle(.secondary)
        }
    }
}

