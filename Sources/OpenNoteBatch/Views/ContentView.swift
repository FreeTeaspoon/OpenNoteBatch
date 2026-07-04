import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } content: {
            ToolPickerView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 380)
        } detail: {
            ToolDetailView()
        }
        .frame(minWidth: 1040, minHeight: 680)
        .toolbar {
            ToolbarItemGroup {
                accountMenu

                Button {
                    model.loadNotebookTree()
                } label: {
                    Label("Reload Notebooks", systemImage: "arrow.clockwise")
                }
                .disabled(model.auth.account == nil || model.isBusy)
                .help("Reload notebooks")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.runSelectedTool()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                .help("Run selected tool")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            ForEach(AccountKind.allCases) { kind in
                Button {
                    model.signIn(kind: kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }

            if model.auth.account != nil {
                Divider()
                Button {
                    model.auth.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Label(model.auth.account == nil ? "Sign In" : "Account", systemImage: "person.crop.circle")
        }
        .help(model.auth.account == nil ? "Sign in" : "Account")
    }
}
