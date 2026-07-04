import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 300, idealWidth: 330, maxWidth: 380)
                .background(.thinMaterial)

            ToolPickerView()
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
                .background(Color(nsColor: .windowBackgroundColor))

            ToolDetailView()
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 1180, minHeight: 720)
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environmentObject(model)
        }
    }
}
