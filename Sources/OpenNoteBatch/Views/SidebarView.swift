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

    let notebook: NotebookNode

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(notebook.sections) { section in
                SectionTreeRow(section: section)
            }
            ForEach(notebook.sectionGroups) { group in
                SectionGroupTreeRow(group: group)
            }
            if model.isLoadingNotebook(notebook) {
                LoadingTreeRow(title: "Loading sections")
            }
        } label: {
            HStack {
                Label(notebook.displayName, systemImage: "book.closed")
                    .lineLimit(1)
                Spacer()
                if model.isLoadingNotebook(notebook) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .tag("notebook:\(notebook.id)")
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                model.selectTreeItem("notebook:\(notebook.id)")
                model.loadNotebookContentsIfNeeded(notebook)
            }
        }
    }
}

private struct SectionGroupTreeRow: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isExpanded = false

    let group: SectionGroupNode

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(group.sections) { section in
                SectionTreeRow(section: section)
            }
            ForEach(group.sectionGroups) { childGroup in
                SectionGroupTreeRow(group: childGroup)
            }
            if model.isLoadingSectionGroup(group) {
                LoadingTreeRow(title: "Loading sections")
            }
        } label: {
            HStack {
                Label(group.displayName, systemImage: "folder")
                    .lineLimit(1)
                Spacer()
                if model.isLoadingSectionGroup(group) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .tag("group:\(group.id)")
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                model.selectTreeItem("group:\(group.id)")
                model.loadSectionGroupContentsIfNeeded(group)
            }
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
                Label(section.displayName, systemImage: "folder")
                    .lineLimit(1)
            }
            .toggleStyle(.checkbox)
        }
        .tag("section:\(section.id)")
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
            Label(page.title, systemImage: "doc.text")
                .lineLimit(1)
        }
        .toggleStyle(.checkbox)
        .tag("page:\(page.id)")
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
