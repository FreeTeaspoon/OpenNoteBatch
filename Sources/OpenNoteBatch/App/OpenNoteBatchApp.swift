import SwiftUI

@main
struct OpenNoteBatchApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup("OpenNote Batch") {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    model.handleCallback(url)
                }
                .task {
                    model.refreshNotebooksOnLaunchIfNeeded()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
