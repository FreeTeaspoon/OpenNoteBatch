import SwiftUI

struct ToolDetailView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    options
                    taskStatus
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            ResultsTableView(results: model.results)
                .frame(minHeight: 280)
        }
        .navigationTitle(model.selectedTool.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.selectedTool.title, systemImage: model.selectedTool.symbol)
                .font(.title.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(2)

            Text(model.selectedTool.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !model.selectedTool.isGraphSupported {
                Label("Public Microsoft Graph support is limited for this tool.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        if model.selectedToolID == .account {
            AccountPanelView()
        } else {
            Form {
                Section("Options") {
                    optionRows
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var optionRows: some View {
        switch model.selectedToolID {
        case .attachmentList:
            Toggle("Include embedded images", isOn: $model.includeImages)
            outputChooser(label: "Save folder")
        case .tagList:
            Text("Scans selected pages for OneNote data-tag markers.")
                .foregroundStyle(.secondary)
        case .replacePageTitle:
            TextField("Find", text: $model.searchText)
            TextField("Replace with", text: $model.replaceText)
            Toggle("Match case", isOn: $model.matchCase)
        case .search:
            TextField("Search content", text: $model.searchText)
            Toggle("Match case", isOn: $model.matchCase)
            Toggle("Search page titles only", isOn: $model.titleOnlySearch)
        case .copySections:
            targetSectionField
        case .exportText, .exportHTML, .backup:
            outputChooser(label: "Store folder")
        case .importText:
            importFileChooser(label: "Text files", extensions: ["txt"])
            targetSectionField
        case .importHTML, .importMacNotes, .importGoogleKeep:
            importFileChooser(label: "HTML files", extensions: ["html", "htm"])
            targetSectionField
        case .importImages:
            importFileChooser(label: "Images", extensions: ["png", "jpg", "jpeg", "gif", "heic", "tiff"])
            targetSectionField
        case .importTree:
            importFolderChooser(label: "Source folder")
            targetSectionField
        case .importEvernote:
            importFileChooser(label: "ENEX file", extensions: ["enex"])
            targetSectionField
        case .restore:
            importFileChooser(label: "Backup manifest", extensions: ["json"])
            targetSectionField
        case .findLost, .sectionSize:
            Label("Run this tool to see the current Graph API limitation details.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .account:
            EmptyView()
        }
    }

    private var targetSectionField: some View {
        TextField(
            "Target section",
            text: $model.targetSectionID,
            prompt: Text("Select a section in the sidebar or paste a section ID")
        )
    }

    private func outputChooser(label: String) -> some View {
        LabeledContent(label) {
            HStack {
                TextField(label, text: Binding(
                    get: { model.outputDirectory?.path ?? "" },
                    set: { model.outputDirectory = $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ))
                .labelsHidden()

                Button {
                    model.chooseOutputFolder()
                } label: {
                    Label("Choose folder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .help("Choose folder")
            }
        }
    }

    private func importFileChooser(label: String, extensions: [String]) -> some View {
        LabeledContent(label) {
            HStack {
                Text(model.importFiles.isEmpty ? "No files selected" : "\(model.importFiles.count) file(s) selected")
                    .foregroundStyle(model.importFiles.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Button {
                    model.chooseImportFiles(extensions: extensions)
                } label: {
                    Label("Choose files", systemImage: "doc.badge.plus")
                }
                .labelStyle(.iconOnly)
                .help("Choose files")
            }
        }
    }

    private func importFolderChooser(label: String) -> some View {
        LabeledContent(label) {
            HStack {
                Text(model.importRoot?.path ?? "No folder selected")
                    .foregroundStyle(model.importRoot == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Button {
                    model.chooseImportRoot()
                } label: {
                    Label("Choose folder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .help("Choose folder")
            }
        }
    }

    private var taskStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Status") {
                HStack {
                    StatusLabel(status: model.task.status)
                    Text(model.statusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            ProgressView(value: model.task.progress)
                .opacity(model.task.status == .ready ? 0.55 : 1)
        }
    }
}

struct ResultsTableView: View {
    let results: [BatchResult]

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "tablecells",
                description: Text("Run a tool to populate this table.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(results) {
                TableColumn("Name") { result in
                    Text(result.name)
                        .lineLimit(1)
                }
                TableColumn("Path") { result in
                    Text(result.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TableColumn("Status") { result in
                    StatusLabel(status: result.status)
                }
                TableColumn("Message") { result in
                    Text(result.message)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct StatusLabel: View {
    let status: BatchStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .foregroundStyle(status.color)
            .lineLimit(1)
    }
}

private extension BatchStatus {
    var title: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .ready: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .failed: "xmark.circle"
        case .unsupported: "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .success: .green
        case .failed: .red
        case .warning, .unsupported: .orange
        case .running: .blue
        case .ready: .secondary
        }
    }
}
