import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accountHeader
            actions
            Divider()
            tree
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.auth.account == nil ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.auth.account?.displayName ?? "Not signed in")
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.auth.account?.email ?? "Microsoft Graph account")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if let error = model.auth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        HStack {
            Menu {
                ForEach(AccountKind.allCases) { kind in
                    Button(kind.title) { model.signIn(kind: kind) }
                }
            } label: {
                Label(model.auth.account == nil ? "Sign In" : "Re Login", systemImage: "person.badge.key")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .help(model.auth.account == nil ? "Sign in" : "Re-login")

            Button {
                model.loadNotebookTree()
            } label: {
                Label("Load", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.auth.account == nil || model.isBusy)

            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28)
            }
            .help("Settings")
        }
        .controlSize(.regular)
    }

    private var tree: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notebooks")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(model.selectedPageIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if model.notebooks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "books.vertical")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text("No Notebook Tree")
                        .font(.title2.weight(.bold))
                    Text("Sign in and load notebooks.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.notebooks) { notebook in
                            DisclosureGroup {
                                ForEach(notebook.sections) { section in
                                    SectionTreeRow(section: section)
                                }
                                ForEach(notebook.sectionGroups) { group in
                                    SectionGroupTreeRow(group: group)
                                }
                            } label: {
                                Label(notebook.displayName, systemImage: "book.closed")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct SectionGroupTreeRow: View {
    let group: SectionGroupNode

    var body: some View {
        DisclosureGroup {
            ForEach(group.sections) { section in
                SectionTreeRow(section: section)
            }
            ForEach(group.sectionGroups) { childGroup in
                SectionGroupTreeRow(group: childGroup)
            }
        } label: {
            Label(group.displayName, systemImage: "folder.badge.gearshape")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.leading, 8)
    }
}

struct SectionTreeRow: View {
    @EnvironmentObject private var model: AppViewModel
    let section: SectionNode

    var body: some View {
        DisclosureGroup {
            ForEach(section.pages) { page in
                Toggle(isOn: Binding(
                    get: { model.selectedPageIDs.contains(page.id) },
                    set: { model.togglePage(page, isSelected: $0) }
                )) {
                    Text(page.title)
                        .lineLimit(1)
                }
                .toggleStyle(.checkbox)
                .font(.caption)
                .padding(.leading, 18)
            }
        } label: {
            Toggle(isOn: Binding(
                get: { section.pages.allSatisfy { model.selectedPageIDs.contains($0.id) } && !section.pages.isEmpty },
                set: { model.toggleSection(section, isSelected: $0) }
            )) {
                Label(section.displayName, systemImage: "folder")
                    .lineLimit(1)
            }
            .toggleStyle(.checkbox)
        }
        .padding(.leading, 8)
        .onTapGesture {
            model.selectedSectionID = section.id
        }
    }
}
