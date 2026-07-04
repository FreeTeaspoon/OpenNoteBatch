import SwiftUI

struct ToolPickerView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Workspace", selection: Binding(
                get: { model.selectedTab },
                set: { model.select(tab: $0) }
            )) {
                ForEach(WorkspaceTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(16)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.visibleTools) { tool in
                        ToolButton(tool: tool, isSelected: model.selectedToolID == tool.id) {
                            model.selectedToolID = tool.id
                            model.results = []
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
    }
}

struct ToolButton: View {
    let tool: ToolDefinition
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 28)
                    .foregroundStyle(isSelected ? .white : .blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(tool.subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(2)
                }
                Spacer()
                if !tool.isGraphSupported {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(isSelected ? .yellow : .orange)
                        .help("Limited by public Microsoft Graph APIs")
                }
            }
            .padding(10)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

