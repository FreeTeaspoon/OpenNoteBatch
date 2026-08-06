import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppViewModel

    private var treeSelection: Binding<String?> {
        Binding(
            get: { model.selectedTreeItemID },
            set: { model.selectTreeItem($0) }
        )
    }

    var body: some View {
        List(selection: treeSelection) {
            Section {
                accountRow
            }

            Section {
                if model.notebooks.isEmpty {
                    ContentUnavailableView(
                        "No Notebooks",
                        systemImage: "books.vertical",
                        description: Text("Sign in, then reload notebooks from the toolbar.")
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                } else if filteredNotebooks.isEmpty {
                    ContentUnavailableView.search(text: model.notebookSearchText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredNotebooks) { notebook in
                        NotebookTreeRow(notebook: notebook)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notebooks")
                    Text("\(model.selectedPageIDs.count) pages selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
                .textCase(nil)
            }
        }
        .navigationTitle("OpenNote Batch")
        .searchable(text: $model.notebookSearchText, placement: .sidebar, prompt: "Search notebooks")
    }

    private var accountRow: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.auth.account?.displayName ?? "Not signed in")
                    .lineLimit(1)
                Text(model.auth.account?.email ?? "Microsoft Graph account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let error = model.auth.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        } icon: {
            Image(systemName: model.auth.account == nil ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
        }
    }

    private var filteredNotebooks: [NotebookNode] {
        let query = model.notebookSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.notebooks }
        return model.notebooks.compactMap { filtered(notebook: $0, query: query) }
    }

    private func filtered(notebook: NotebookNode, query: String) -> NotebookNode? {
        if notebook.displayName.localizedCaseInsensitiveContains(query) {
            return notebook
        }

        var copy = notebook
        copy.sections = notebook.sections.compactMap { filtered(section: $0, query: query) }
        copy.sectionGroups = notebook.sectionGroups.compactMap { filtered(group: $0, query: query) }
        return copy.sections.isEmpty && copy.sectionGroups.isEmpty ? nil : copy
    }

    private func filtered(group: SectionGroupNode, query: String) -> SectionGroupNode? {
        if group.displayName.localizedCaseInsensitiveContains(query) {
            return group
        }

        var copy = group
        copy.sections = group.sections.compactMap { filtered(section: $0, query: query) }
        copy.sectionGroups = group.sectionGroups.compactMap { filtered(group: $0, query: query) }
        return copy.sections.isEmpty && copy.sectionGroups.isEmpty ? nil : copy
    }

    private func filtered(section: SectionNode, query: String) -> SectionNode? {
        if section.displayName.localizedCaseInsensitiveContains(query) {
            return section
        }

        var copy = section
        copy.pages = section.pages.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return copy.pages.isEmpty ? nil : copy
    }
}

private struct NotebookTreeRow: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isExpanded = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    let notebook: NotebookNode

    private var canRename: Bool {
        !model.isBusy && model.auth.account != nil
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(TreeChild.sorted(sections: notebook.sections, groups: notebook.sectionGroups)) { child in
                switch child {
                case .section(let section):
                    SectionTreeRow(section: section)
                case .group(let group):
                    SectionGroupTreeRow(group: group)
                }
            }
            if model.isLoadingNotebook(notebook) {
                LoadingTreeRow(title: "Loading sections")
            }
        } label: {
            HStack(spacing: 8) {
                if isRenaming {
                    Image(systemName: "book.closed")
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 18, alignment: .center)

                    TextField("Notebook name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .focused($renameFieldFocused)
                        .onSubmit {
                            commitRename()
                        }
                        .onExitCommand {
                            cancelRename()
                        }

                    Button {
                        commitRename()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Save notebook name")

                    Button {
                        cancelRename()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel notebook rename")
                } else {
                    TreeItemLabel(title: notebook.displayName, systemImage: "book.closed")
                }
                Spacer()
                if model.isLoadingNotebook(notebook) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
        .tag("notebook:\(notebook.id)")
        .contextMenu {
            Button {
                beginRename()
            } label: {
                Label("Rename Notebook", systemImage: "pencil")
            }
            .disabled(!canRename)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                model.selectTreeItem("notebook:\(notebook.id)")
                model.loadNotebookContentsIfNeeded(notebook)
            }
        }
    }

    private func beginRename() {
        guard canRename else { return }
        renameText = notebook.displayName
        isRenaming = true
        Task { @MainActor in
            renameFieldFocused = true
        }
    }

    private func commitRename() {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != notebook.displayName else {
            cancelRename()
            return
        }

        isRenaming = false
        renameFieldFocused = false
        model.renameNotebook(notebook, newName: newName)
    }

    private func cancelRename() {
        isRenaming = false
        renameFieldFocused = false
        renameText = ""
    }
}

private struct SectionGroupTreeRow: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isExpanded = false

    let group: SectionGroupNode

    private var isSelected: Binding<Bool> {
        Binding(
            get: { model.isSectionGroupSelected(group) },
            set: { model.toggleSectionGroup(group, isSelected: $0) }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(TreeChild.sorted(sections: group.sections, groups: group.sectionGroups)) { child in
                switch child {
                case .section(let section):
                    SectionTreeRow(section: section)
                case .group(let childGroup):
                    SectionGroupTreeRow(group: childGroup)
                }
            }
            if model.isLoadingSectionGroup(group) {
                LoadingTreeRow(title: "Loading sections")
            }
        } label: {
            HStack {
                Toggle(isOn: isSelected) {
                    TreeItemLabel(title: group.displayName, systemImage: "folder")
                }
                .toggleStyle(.checkbox)
                Spacer()
                if model.isLoadingSectionGroup(group) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
        .tag("group:\(group.id)")
        .contextMenu {
            Button {
                model.renameSectionGroup(group)
            } label: {
                Label("Rename Folder", systemImage: "pencil")
            }
            .disabled(model.isBusy || model.auth.account == nil)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                model.selectTreeItem("group:\(group.id)")
                model.loadSectionGroupContentsIfNeeded(group)
            }
        }
    }
}

private enum TreeChild: Identifiable {
    case section(SectionNode)
    case group(SectionGroupNode)

    var id: String {
        switch self {
        case .section(let section): "section:\(section.id)"
        case .group(let group): "group:\(group.id)"
        }
    }

    private var displayName: String {
        switch self {
        case .section(let section): section.displayName
        case .group(let group): group.displayName
        }
    }

    private var createdDateTime: Date? {
        switch self {
        case .section(let section): section.createdDateTime
        case .group(let group): group.createdDateTime
        }
    }

    static func sorted(sections: [SectionNode], groups: [SectionGroupNode]) -> [TreeChild] {
        (sections.map(TreeChild.section) + groups.map(TreeChild.group))
            .sorted {
                if let lhsDate = $0.createdDateTime, let rhsDate = $1.createdDateTime, lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                if $0.createdDateTime != nil, $1.createdDateTime == nil { return true }
                if $0.createdDateTime == nil, $1.createdDateTime != nil { return false }
                let comparison = $0.displayName.localizedStandardCompare($1.displayName)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
    }
}

private struct SectionTreeRow: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isExpanded = false

    let section: SectionNode

    private var isSelected: Binding<Bool> {
        Binding(
            get: {
                !section.pages.isEmpty && section.pages.allSatisfy { model.selectedPageIDs.contains($0.id) }
            },
            set: { model.toggleSection(section, isSelected: $0) }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(section.pages) { page in
                PageTreeRow(page: page)
            }
            if model.isLoadingSection(section) {
                LoadingTreeRow(title: "Loading pages")
            } else if model.hasLoadedSection(section) && section.pages.isEmpty {
                Text("No pages")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Toggle(isOn: isSelected) {
                TreeItemLabel(title: section.displayName, systemImage: "folder")
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 2)
        }
        .tag("section:\(section.id)")
        .contextMenu {
            Button {
                model.renameSection(section)
            } label: {
                Label("Rename Section", systemImage: "pencil")
            }
            .disabled(model.isBusy || model.auth.account == nil)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                model.selectTreeItem("section:\(section.id)")
                model.loadSectionPagesIfNeeded(section)
            }
        }
    }
}

private struct PageTreeRow: View {
    @EnvironmentObject private var model: AppViewModel

    let page: PageNode

    private var isSelected: Binding<Bool> {
        Binding(
            get: { model.selectedPageIDs.contains(page.id) },
            set: { model.togglePage(page, isSelected: $0) }
        )
    }

    var body: some View {
        Toggle(isOn: isSelected) {
            TreeItemLabel(title: page.title, systemImage: "doc.text")
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 1)
        .tag("page:\(page.id)")
    }
}

private struct TreeItemLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, alignment: .center)
            Text(title)
                .lineLimit(1)
        }
    }
}

private struct LoadingTreeRow: View {
    let title: String

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.secondary)
        } icon: {
            ProgressView()
                .controlSize(.small)
        }
    }
}
