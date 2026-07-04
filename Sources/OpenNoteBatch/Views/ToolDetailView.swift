import SwiftUI

struct ToolDetailView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                options
                progress
                ResultsTableView(results: model.results)
                    .frame(minHeight: 360)
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label(model.selectedTool.title, systemImage: model.selectedTool.symbol)
                    .font(.largeTitle.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(model.selectedTool.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !model.selectedTool.isGraphSupported {
                    Label("This tool is visible for feature parity, but public Microsoft Graph support is limited.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button {
                model.runSelectedTool()
            } label: {
                Image(systemName: model.isBusy ? "stop.circle.fill" : "play.fill")
                    .font(.system(size: 44, weight: .bold))
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
            .help("Run selected tool")
        }
    }

    @ViewBuilder
    private var options: some View {
        switch model.selectedToolID {
        case .attachmentList:
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Include embedded images", isOn: $model.includeImages)
                outputChooser(label: "Save Folder")
            }
        case .tagList:
            Text("Scans selected pages for OneNote `data-tag` markers.")
                .foregroundStyle(.secondary)
        case .replacePageTitle:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search", text: $model.searchText)
                TextField("Replace", text: $model.replaceText)
                Toggle("Match case", isOn: $model.matchCase)
            }
        case .search:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search content", text: $model.searchText)
                HStack {
                    Toggle("Match case", isOn: $model.matchCase)
                    Toggle("Search in page title only", isOn: $model.titleOnlySearch)
                }
            }
        case .copySections:
            targetSectionField
        case .exportText, .exportHTML, .backup:
            outputChooser(label: "Store Folder")
        case .importText:
            importFileChooser(label: "Text Files", extensions: ["txt"])
            targetSectionField
        case .importHTML, .importMacNotes, .importGoogleKeep:
            importFileChooser(label: "HTML Files", extensions: ["html", "htm"])
            targetSectionField
        case .importImages:
            importFileChooser(label: "Images", extensions: ["png", "jpg", "jpeg", "gif", "heic", "tiff"])
            targetSectionField
        case .importTree:
            importFolderChooser(label: "Source Folder")
            targetSectionField
        case .importEvernote:
            importFileChooser(label: "ENEX File", extensions: ["enex"])
            targetSectionField
        case .restore:
            importFileChooser(label: "Backup Manifest", extensions: ["json"])
            targetSectionField
        case .account:
            AccountPanelView()
        default:
            Text("Run this tool to see available Graph support.")
                .foregroundStyle(.secondary)
        }
    }

    private var targetSectionField: some View {
        TextField("Target section ID (or select a section in the sidebar)", text: $model.targetSectionID)
            .textFieldStyle(.roundedBorder)
    }

    private func outputChooser(label: String) -> some View {
        HStack {
            TextField(label, text: Binding(
                get: { model.outputDirectory?.path ?? "" },
                set: { model.outputDirectory = URL(fileURLWithPath: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            Button {
                model.chooseOutputFolder()
            } label: {
                Image(systemName: "folder")
            }
            .help("Choose folder")
        }
    }

    private func importFileChooser(label: String, extensions: [String]) -> some View {
        HStack {
            Text(model.importFiles.isEmpty ? label : "\(model.importFiles.count) file(s) selected")
                .foregroundStyle(model.importFiles.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            Button {
                model.chooseImportFiles(extensions: extensions)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
        }
    }

    private func importFolderChooser(label: String) -> some View {
        HStack {
            Text(model.importRoot?.path ?? label)
                .foregroundStyle(model.importRoot == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            Button {
                model.chooseImportRoot()
            } label: {
                Image(systemName: "folder")
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.task.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: model.task.status))
            }
            ProgressView(value: model.task.progress)
        }
    }

    private func color(for status: BatchStatus) -> Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .warning, .unsupported: .orange
        case .running: .blue
        default: .secondary
        }
    }
}

struct ResultsTableView: View {
    let results: [BatchResult]

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView("No Results", systemImage: "tablecells", description: Text("Run a tool to populate this table."))
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
                    Text(result.status.rawValue.capitalized)
                        .foregroundStyle(statusColor(result.status))
                }
                TableColumn("Message") { result in
                    Text(result.message)
                        .lineLimit(2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func statusColor(_ status: BatchStatus) -> Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .warning, .unsupported: .orange
        case .running: .blue
        default: .secondary
        }
    }
}
