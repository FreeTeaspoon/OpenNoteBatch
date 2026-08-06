import SwiftUI

struct ToolPickerView: View {
    @EnvironmentObject private var model: AppViewModel

    private var selectedTool: Binding<ToolID?> {
        Binding(
            get: { model.selectedToolID },
            set: { toolID in
                if let toolID {
                    model.select(toolID: toolID)
                }
            }
        )
    }

    var body: some View {
        List(selection: selectedTool) {
            ForEach(WorkspaceTab.allCases) { tab in
                ForEach(groupedTools(for: tab)) { group in
                    Section {
                        ForEach(group.tools) { tool in
                            ToolRow(tool: tool)
                                .tag(tool.id)
                                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                        }
                    } header: {
                        Text("\(tab.rawValue) · \(group.title)")
                            .padding(.top, 6)
                            .padding(.bottom, 4)
                            .textCase(nil)
                    }
                }
            }

            if allFilteredTools.isEmpty {
                ContentUnavailableView.search(text: model.toolSearchText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("Tools")
        .searchable(text: $model.toolSearchText, prompt: "Search tools")
    }

    private var allFilteredTools: [ToolDefinition] {
        WorkspaceTab.allCases.flatMap { filteredTools(for: $0) }
    }

    private func filteredTools(for tab: WorkspaceTab) -> [ToolDefinition] {
        let query = model.toolSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tools = ToolDefinition.all.filter { $0.tab == tab }
        guard !query.isEmpty else { return tools }
        return tools.filter { tool in
            tool.title.localizedCaseInsensitiveContains(query)
                || tool.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private func groupedTools(for tab: WorkspaceTab) -> [ToolSection] {
        var sections: [ToolSection] = []

        for tool in filteredTools(for: tab) {
            if let index = sections.firstIndex(where: { $0.id == tool.group }) {
                sections[index].tools.append(tool)
            } else {
                sections.append(ToolSection(id: tool.group, title: tool.group, tools: [tool]))
            }
        }

        return sections
    }
}

private struct ToolSection: Identifiable {
    let id: String
    let title: String
    var tools: [ToolDefinition]
}

private struct ToolRow: View {
    let tool: ToolDefinition

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tool.symbol)
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .imageScale(.medium)
                .frame(width: 22, height: 20, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .lineLimit(1)
                Text(tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !tool.isGraphSupported {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                    .help("Limited by public Microsoft Graph APIs")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
