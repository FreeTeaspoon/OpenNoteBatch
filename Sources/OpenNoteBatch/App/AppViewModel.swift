import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings = AppSettings() {
        didSet { saveSettings() }
    }
    @Published var selectedTab: WorkspaceTab = .export
    @Published var selectedToolID: ToolID = .exportAttachmentsAndImages
    @Published var selectedNotebookID: String?
    @Published var selectedTreeItemID: String?
    @Published var toolSearchText = ""
    @Published var notebookSearchText = ""
    @Published var notebooks: [NotebookNode] = []
    @Published var selectedPageIDs: Set<String> = []
    @Published var selectedSectionID: String?
    @Published var targetSectionID = ""
    @Published var outputDirectory: URL? {
        didSet {
            settings.outputDirectoryPath = outputDirectory?.path
        }
    }
    @Published var importFiles: [URL] = []
    @Published var importRoot: URL?
    @Published var includeAttachments = true
    @Published var includeImages = true
    @Published var includeDrawings = true
    @Published var createImagePDF = true
    @Published var matchCase = false
    @Published var titleOnlySearch = true
    @Published var searchText = ""
    @Published var replaceText = ""
    @Published var task = BatchTask(title: "Ready", progress: 0, status: .ready)
    @Published var results: [BatchResult] = []
    @Published var isBusy = false
    @Published var statusMessage = "Sign in, load notebooks, then choose a tool."
    @Published var showSettings = false
    @Published private(set) var loadingNodeIDs: Set<String> = []
    @Published private(set) var loadedNodeIDs: Set<String> = []

    let auth = AuthService()
    private var cancellables = Set<AnyCancellable>()
    private var pendingSectionSelections: [String: Bool] = [:]
    private var pendingSectionGroupSelections: [String: Bool] = [:]
    private var sectionGroupSelectionStates: [String: Bool] = [:]

    var selectedTool: ToolDefinition {
        ToolDefinition.all.first { $0.id == selectedToolID } ?? ToolDefinition.all[0]
    }

    var visibleTools: [ToolDefinition] {
        ToolDefinition.all.filter { $0.tab == selectedTab }
    }

    var filteredVisibleTools: [ToolDefinition] {
        let query = toolSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleTools }
        return visibleTools.filter { tool in
            tool.title.localizedCaseInsensitiveContains(query)
                || tool.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedPages: [PageNode] {
        allPages.filter { selectedPageIDs.contains($0.id) }
    }

    var allPages: [PageNode] {
        notebooks.flatMap { notebook in
            notebook.sections.flatMap(\.pages) + pages(in: notebook.sectionGroups)
        }
    }

    init() {
        auth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        loadSettings()
        if let path = settings.outputDirectoryPath, !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path)
        }
    }

    func select(tab: WorkspaceTab) {
        selectedTab = tab
        selectedToolID = ToolDefinition.all.first { $0.tab == tab }?.id ?? .exportAttachmentsAndImages
        results = []
    }

    func select(toolID: ToolID) {
        selectedToolID = toolID
        selectedTab = selectedTool.tab
        results = []
    }

    func selectTreeItem(_ id: String?) {
        selectedTreeItemID = id
        guard let id else { return }

        if id.hasPrefix("notebook:") {
            selectedNotebookID = String(id.dropFirst("notebook:".count))
        } else if id.hasPrefix("section:") {
            selectedSectionID = String(id.dropFirst("section:".count))
        }
    }

    func signIn(kind: AccountKind) {
        Task {
            do {
                try await auth.signIn(accountKind: kind, settings: settings)
            } catch {
                results = [.init(name: kind.title, path: "", status: .failed, message: error.localizedDescription)]
            }
        }
    }

    func handleCallback(_ url: URL) {
        Task { await auth.handleCallback(url) }
    }

    func loadNotebookTree() {
        Task {
            await self.runBusy(title: "Loading notebooks") {
                self.statusMessage = "Connecting to Microsoft Graph..."
                let repository = try await self.makeRepository()
                self.statusMessage = "Loading notebooks..."
                let loadedNotebooks = try await repository.notebooks()
                self.selectedPageIDs = []
                self.selectedSectionID = nil
                self.pendingSectionSelections = [:]
                self.pendingSectionGroupSelections = [:]
                self.sectionGroupSelectionStates = [:]
                self.loadingNodeIDs = []
                self.loadedNodeIDs = []
                self.notebooks = loadedNotebooks
                self.selectedNotebookID = loadedNotebooks.first?.id
                self.selectedTreeItemID = loadedNotebooks.first.map { "notebook:\($0.id)" }
                self.statusMessage = "Loaded \(loadedNotebooks.count) notebook(s)."
                return [.init(name: "Notebook tree", path: "", status: .success, message: "Loaded notebooks. Expand a notebook to load its sections.")]
            }
        }
    }

    func loadNotebookContentsIfNeeded(_ notebook: NotebookNode) {
        let key = nodeKey("notebook", notebook.id)
        guard !loadedNodeIDs.contains(key), !loadingNodeIDs.contains(key) else { return }
        loadingNodeIDs.insert(key)
        statusMessage = "Loading sections for \(notebook.displayName)..."
        Task {
            do {
                let repository = try await self.makeRepository()
                async let sections = repository.sections(notebookID: notebook.id)
                async let groups = repository.sectionGroups(notebookID: notebook.id)
                let loadedSections = try await sections
                let loadedGroups = try await groups
                self.updateNotebook(id: notebook.id) {
                    $0.sections = loadedSections
                    $0.sectionGroups = loadedGroups
                }
                self.loadedNodeIDs.insert(key)
                self.statusMessage = "Loaded sections for \(notebook.displayName)."
            } catch {
                self.results = [.init(name: notebook.displayName, path: "", status: .failed, message: error.localizedDescription)]
                self.statusMessage = error.localizedDescription
            }
            self.loadingNodeIDs.remove(key)
        }
    }

    func loadSectionGroupContentsIfNeeded(_ group: SectionGroupNode) {
        let key = nodeKey("group", group.id)
        guard !loadedNodeIDs.contains(key), !loadingNodeIDs.contains(key) else { return }
        loadingNodeIDs.insert(key)
        statusMessage = "Loading sections for \(group.displayName)..."
        Task {
            do {
                let repository = try await self.makeRepository()
                let path = [group.parentPath, group.displayName].filter { !$0.isEmpty }.joined(separator: " / ")
                async let sections = repository.sections(
                    sectionGroupID: group.id,
                    notebookID: group.notebookID,
                    groupPath: path
                )
                async let childGroups = repository.childSectionGroups(
                    sectionGroupID: group.id,
                    notebookID: group.notebookID,
                    parentPath: path
                )
                let loadedSections = try await sections
                let loadedChildGroups = try await childGroups
                self.updateSectionGroup(id: group.id) {
                    $0.sections = loadedSections
                    $0.sectionGroups = loadedChildGroups
                }
                self.loadedNodeIDs.insert(key)
                if let pendingSelection = self.pendingSectionGroupSelections.removeValue(forKey: group.id) {
                    self.applySectionGroupSelection(
                        sections: loadedSections,
                        groups: loadedChildGroups,
                        isSelected: pendingSelection
                    )
                }
                self.statusMessage = "Loaded sections for \(group.displayName)."
            } catch {
                self.results = [.init(name: group.displayName, path: "", status: .failed, message: error.localizedDescription)]
                self.statusMessage = error.localizedDescription
            }
            self.loadingNodeIDs.remove(key)
        }
    }

    func loadSectionPagesIfNeeded(_ section: SectionNode) {
        let key = nodeKey("section", section.id)
        guard !loadedNodeIDs.contains(key), !loadingNodeIDs.contains(key) else { return }
        loadingNodeIDs.insert(key)
        statusMessage = "Loading pages for \(section.displayName)..."
        Task {
            do {
                let repository = try await self.makeRepository()
                var pages = try await repository.pages(sectionID: section.id)
                let sectionName = [section.groupPath, section.displayName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " / ")
                pages = pages.map {
                    var page = $0
                    page.notebookName = self.notebookName(for: section)
                    page.sectionName = sectionName
                    return page
                }
                self.updateSection(id: section.id) {
                    $0.pages = pages
                }
                if let pendingSelection = self.pendingSectionSelections.removeValue(forKey: section.id) {
                    let pageIDs = pages.map(\.id)
                    if pendingSelection {
                        self.selectedPageIDs.formUnion(pageIDs)
                    } else {
                        self.selectedPageIDs.subtract(pageIDs)
                    }
                }
                self.loadedNodeIDs.insert(key)
                self.statusMessage = "Loaded \(pages.count) page(s) for \(section.displayName)."
            } catch {
                self.results = [.init(name: section.displayName, path: "", status: .failed, message: error.localizedDescription)]
                self.statusMessage = error.localizedDescription
            }
            self.loadingNodeIDs.remove(key)
        }
    }

    func isLoadingNotebook(_ notebook: NotebookNode) -> Bool {
        loadingNodeIDs.contains(nodeKey("notebook", notebook.id))
    }

    func isLoadingSectionGroup(_ group: SectionGroupNode) -> Bool {
        loadingNodeIDs.contains(nodeKey("group", group.id))
    }

    func isLoadingSection(_ section: SectionNode) -> Bool {
        loadingNodeIDs.contains(nodeKey("section", section.id))
    }

    func hasLoadedSection(_ section: SectionNode) -> Bool {
        loadedNodeIDs.contains(nodeKey("section", section.id))
    }

    func hasLoadedSectionGroup(_ group: SectionGroupNode) -> Bool {
        loadedNodeIDs.contains(nodeKey("group", group.id))
    }

    func isSectionGroupSelected(_ group: SectionGroupNode) -> Bool {
        if let explicit = sectionGroupSelectionStates[group.id] {
            return explicit
        }
        let descendantPages = group.sections.flatMap(\.pages) + pages(in: group.sectionGroups)
        return !descendantPages.isEmpty
            && descendantPages.allSatisfy { selectedPageIDs.contains($0.id) }
    }

    func togglePage(_ page: PageNode, isSelected: Bool) {
        sectionGroupSelectionStates.removeAll()
        selectedTreeItemID = "page:\(page.id)"
        setPageSelection(page, isSelected: isSelected)
    }

    func toggleSection(_ section: SectionNode, isSelected: Bool) {
        sectionGroupSelectionStates.removeAll()
        selectedSectionID = section.id
        selectedTreeItemID = "section:\(section.id)"
        setSectionSelection(section, isSelected: isSelected)
    }

    func toggleSectionGroup(_ group: SectionGroupNode, isSelected: Bool) {
        selectedTreeItemID = "group:\(group.id)"
        setSectionGroupSelection(group, isSelected: isSelected)
        selectedTreeItemID = "group:\(group.id)"
    }

    private func setPageSelection(_ page: PageNode, isSelected: Bool) {
        if isSelected {
            selectedPageIDs.insert(page.id)
        } else {
            selectedPageIDs.remove(page.id)
        }
    }

    private func setSectionSelection(_ section: SectionNode, isSelected: Bool) {
        if section.pages.isEmpty && !hasLoadedSection(section) {
            pendingSectionSelections[section.id] = isSelected
            loadSectionPagesIfNeeded(section)
            return
        }
        for page in section.pages {
            setPageSelection(page, isSelected: isSelected)
        }
    }

    private func setSectionGroupSelection(_ group: SectionGroupNode, isSelected: Bool) {
        sectionGroupSelectionStates[group.id] = isSelected
        if !hasLoadedSectionGroup(group) {
            pendingSectionGroupSelections[group.id] = isSelected
            loadSectionGroupContentsIfNeeded(group)
            return
        }
        applySectionGroupSelection(
            sections: group.sections,
            groups: group.sectionGroups,
            isSelected: isSelected
        )
    }

    private func applySectionGroupSelection(
        sections: [SectionNode],
        groups: [SectionGroupNode],
        isSelected: Bool
    ) {
        for section in sections {
            setSectionSelection(section, isSelected: isSelected)
        }
        for group in groups {
            setSectionGroupSelection(group, isSelected: isSelected)
        }
    }

    func renameNotebook(_ notebook: NotebookNode) {
        guard let newName = promptForRename(title: "Rename Notebook", currentName: notebook.displayName) else { return }
        Task {
            await runBusy(title: "Rename Notebook") {
                let repository = try await self.makeRepository()
                try await repository.renameNotebook(notebookID: notebook.id, displayName: newName)
                self.updateNotebook(id: notebook.id) {
                    $0.displayName = newName
                }
                self.selectedNotebookID = notebook.id
                self.selectedTreeItemID = "notebook:\(notebook.id)"
                self.statusMessage = "Renamed notebook to \(newName)."
                return [.init(name: notebook.displayName, path: newName, status: .success, message: "Renamed notebook.")]
            }
        }
    }

    func renameSectionGroup(_ group: SectionGroupNode) {
        guard let newName = promptForRename(title: "Rename Folder", currentName: group.displayName) else { return }
        Task {
            await runBusy(title: "Rename Folder") {
                let repository = try await self.makeRepository()
                try await repository.renameSectionGroup(sectionGroupID: group.id, displayName: newName)
                self.updateSectionGroup(id: group.id) {
                    $0.displayName = newName
                }
                self.selectedTreeItemID = "group:\(group.id)"
                self.statusMessage = "Renamed folder to \(newName)."
                return [.init(name: group.displayName, path: newName, status: .success, message: "Renamed folder.")]
            }
        }
    }

    func renameSection(_ section: SectionNode) {
        guard let newName = promptForRename(title: "Rename Section", currentName: section.displayName) else { return }
        Task {
            await runBusy(title: "Rename Section") {
                let repository = try await self.makeRepository()
                try await repository.renameSection(sectionID: section.id, displayName: newName)
                self.updateSection(id: section.id) {
                    $0.displayName = newName
                    for pageIndex in $0.pages.indices {
                        let sectionName = [$0.groupPath, newName]
                            .filter { !$0.isEmpty }
                            .joined(separator: " / ")
                        $0.pages[pageIndex].sectionName = sectionName
                    }
                }
                self.selectedSectionID = section.id
                self.selectedTreeItemID = "section:\(section.id)"
                self.statusMessage = "Renamed section to \(newName)."
                return [.init(name: section.displayName, path: newName, status: .success, message: "Renamed section.")]
            }
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }

    func chooseImportFiles(extensions: [String]? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if let extensions {
            panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) }
        }
        if panel.runModal() == .OK {
            importFiles = panel.urls
        }
    }

    func chooseImportRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            importRoot = panel.url
        }
    }

    func runSelectedTool() {
        Task {
            await self.runBusy(title: self.selectedTool.title) {
                let client = try await self.makeGraphClient()
                let repository = OneNoteRepository(client: client)
                let exportService = ExportService(repository: repository, client: client)
                let importService = ImportService(repository: repository, client: client)
                let runner = BatchRunner(repository: repository, exportService: exportService, importService: importService)
                let progress = self.progressReporter(title: self.selectedTool.title)

                switch self.selectedToolID {
                case .tagList:
                    return try await self.runTagList(repository: repository, progress: progress)
                case .replacePageTitle:
                    return try await self.runReplacePageTitle(repository: repository, progress: progress)
                case .search:
                    return try await self.runSearch(repository: repository, progress: progress)
                case .findLost, .sectionSize:
                    return runner.unsupported(self.selectedTool)
                case .copySections:
                    return try await self.runCopySections(repository: repository, progress: progress)
                case .exportText:
                    return try await exportService.exportText(
                        pages: self.requiredPages(),
                        outputDirectory: self.resolvedOutputDirectory(),
                        progress: progress
                    )
                case .exportHTML:
                    return try await exportService.exportHTML(
                        pages: self.requiredPages(),
                        outputDirectory: self.resolvedOutputDirectory(),
                        progress: progress
                    )
                case .exportAttachmentsAndImages:
                    return try await exportService.exportAttachmentsAndImages(
                        pages: self.requiredPages(),
                        outputDirectory: self.resolvedOutputDirectory(),
                        includeAttachments: self.includeAttachments,
                        includeImages: self.includeImages,
                        includeDrawings: self.includeDrawings,
                        createPDF: self.createImagePDF,
                        progress: progress
                    )
                case .backup:
                    return try await exportService.backup(
                        pages: self.requiredPages(),
                        outputDirectory: self.resolvedOutputDirectory(),
                        progress: progress
                    )
                case .importText:
                    return try await importService.importText(
                        files: self.requiredImportFiles(),
                        sectionID: self.requiredTargetSection(),
                        progress: progress
                    )
                case .importHTML, .importMacNotes, .importGoogleKeep:
                    return try await importService.importHTML(
                        files: self.requiredImportFiles(),
                        sectionID: self.requiredTargetSection(),
                        progress: progress
                    )
                case .importImages:
                    return try await importService.importImages(
                        files: self.requiredImportFiles(),
                        sectionID: self.requiredTargetSection(),
                        progress: progress
                    )
                case .importTree:
                    guard let importRoot = self.importRoot else { throw OpenNoteError.selectionRequired("Choose a source folder first.") }
                    return try await importService.importTree(
                        root: importRoot,
                        sectionID: self.requiredTargetSection(),
                        includeText: true,
                        includeHTML: true,
                        progress: progress
                    )
                case .importEvernote:
                    guard let file = try self.requiredImportFiles().first else { throw OpenNoteError.selectionRequired("Choose an ENEX file first.") }
                    return try await importService.importEvernote(
                        file: file,
                        sectionID: self.requiredTargetSection(),
                        progress: progress
                    )
                case .restore:
                    return try await self.runRestore(importService: importService, progress: progress)
                case .account:
                    return self.accountResults()
                }
            }
        }
    }

    private func runBusy(title: String, work: @escaping () async throws -> [BatchResult]) async {
        isBusy = true
        task = BatchTask(title: title, progress: 0, status: .running)
        results = []
        statusMessage = "\(title)..."
        do {
            let output = try await work()
            results = output
            task = BatchTask(title: title, progress: 1, status: output.contains(where: { $0.status == .failed }) ? .failed : .success)
            statusMessage = "Finished \(title)."
        } catch {
            results = [.init(name: title, path: "", status: .failed, message: error.localizedDescription)]
            task = BatchTask(title: title, progress: 1, status: .failed)
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func progressReporter(title: String) -> BatchProgressUpdate {
        { completed, total, message in
            await MainActor.run {
                let total = max(total, 1)
                let rawProgress = Double(completed) / Double(total)
                let boundedProgress = min(max(rawProgress, 0), 0.98)
                let progress = max(self.task.progress, boundedProgress)
                self.task = BatchTask(title: title, progress: progress, status: .running)
                self.statusMessage = message
            }
        }
    }

    private func promptForRename(title: String, currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a new name."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = currentName
        textField.selectText(nil)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != currentName else { return nil }
        return newName
    }

    private func makeGraphClient() async throws -> GraphClient {
        let (token, root) = try await auth.validAccessToken(settings: settings)
        return GraphClient(accessToken: token, root: root)
    }

    private func makeRepository() async throws -> OneNoteRepository {
        OneNoteRepository(client: try await makeGraphClient())
    }

    private func requiredPages() throws -> [PageNode] {
        let pages = selectedPages
        guard !pages.isEmpty else { throw OpenNoteError.selectionRequired("Select one or more pages in the notebook browser.") }
        return pages
    }

    private func requiredImportFiles() throws -> [URL] {
        guard !importFiles.isEmpty else { throw OpenNoteError.selectionRequired("Choose one or more files first.") }
        return importFiles
    }

    private func requiredTargetSection() throws -> String {
        let explicit = targetSectionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        if let selectedSectionID { return selectedSectionID }
        throw OpenNoteError.selectionRequired("Select a destination section or paste a target section ID.")
    }

    private func resolvedOutputDirectory() throws -> URL {
        if let outputDirectory { return outputDirectory }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return downloads.appendingPathComponent("OpenNote Batch")
    }

    private func runTagList(repository: OneNoteRepository, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        var output: [BatchResult] = []
        let pages = try requiredPages()
        for (index, page) in pages.enumerated() {
            let tags = try await repository.tags(on: page)
            output.append(contentsOf: tags)
            if tags.isEmpty {
                output.append(.init(name: page.title, path: page.sectionName ?? "", status: .warning, message: "No tags found."))
            }
            await progress?(index + 1, pages.count, "Scanned \(page.title).")
        }
        return output
    }

    private func runSearch(repository: OneNoteRepository, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        let pages = selectedPages.isEmpty ? allPages : selectedPages
        guard !pages.isEmpty else { throw OpenNoteError.selectionRequired("Load notebooks and select pages, or search all loaded pages.") }
        return try await repository.search(
            query: searchText,
            pages: pages,
            titleOnly: titleOnlySearch,
            matchCase: matchCase,
            progress: progress
        )
    }

    private func runReplacePageTitle(repository: OneNoteRepository, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        guard !searchText.isEmpty else { throw OpenNoteError.selectionRequired("Enter text to find in page titles.") }
        let pages = try requiredPages()
        var output: [BatchResult] = []
        for (index, page) in pages.enumerated() {
            let source = matchCase ? page.title : page.title.lowercased()
            let needle = matchCase ? searchText : searchText.lowercased()
            if source.contains(needle) {
                let newTitle = matchCase
                    ? page.title.replacingOccurrences(of: searchText, with: replaceText)
                    : page.title.replacingOccurrences(of: searchText, with: replaceText, options: .caseInsensitive)
                try await repository.renamePage(pageID: page.id, title: newTitle)
                output.append(.init(name: page.title, path: newTitle, status: .success, message: "Renamed page."))
                await progress?(index + 1, pages.count, "Renamed \(page.title).")
            } else {
                await progress?(index + 1, pages.count, "Checked \(page.title).")
            }
        }
        return output.isEmpty ? [.init(name: "Replace Page Title", path: "", status: .warning, message: "No selected page titles matched.")] : output
    }

    private func runCopySections(repository: OneNoteRepository, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        let target = try requiredTargetSection()
        var output: [BatchResult] = []
        let pages = try requiredPages()
        for (index, page) in pages.enumerated() {
            let html = try await repository.pageContent(pageID: page.id)
            try await repository.createPage(sectionID: target, html: html)
            output.append(.init(name: page.title, path: target, status: .success, message: "Copied page HTML into target section."))
            await progress?(index + 1, pages.count, "Copied \(page.title).")
        }
        return output
    }

    private func runRestore(importService: ImportService, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        guard let manifestFile = importFiles.first else {
            throw OpenNoteError.selectionRequired("Choose a manifest.json file first.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestFile))
        let htmlFiles = manifest.pages.map { URL(fileURLWithPath: $0.htmlPath) }
        return try await importService.importHTML(files: htmlFiles, sectionID: requiredTargetSection(), progress: progress)
    }

    private func accountResults() -> [BatchResult] {
        guard let account = auth.account else {
            return [.init(name: "Microsoft Account", path: "", status: .warning, message: "Not signed in.")]
        }
        return [
            .init(name: account.displayName, path: account.email, status: .success, message: account.accountKind.title),
            .init(name: "Permissions", path: "", status: .ready, message: settings.permissionPreset.scopes.joined(separator: ", "))
        ]
    }

    private func pages(in groups: [SectionGroupNode]) -> [PageNode] {
        groups.flatMap { group in
            group.sections.flatMap(\.pages) + pages(in: group.sectionGroups)
        }
    }

    private func nodeKey(_ type: String, _ id: String) -> String {
        "\(type):\(id)"
    }

    private func notebookName(for section: SectionNode) -> String? {
        guard let notebookID = section.notebookID else { return nil }
        return notebooks.first { $0.id == notebookID }?.displayName
    }

    private func updateNotebook(id: String, transform: (inout NotebookNode) -> Void) {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        transform(&notebooks[index])
    }

    private func updateSection(id: String, transform: (inout SectionNode) -> Void) {
        for notebookIndex in notebooks.indices {
            if let sectionIndex = notebooks[notebookIndex].sections.firstIndex(where: { $0.id == id }) {
                transform(&notebooks[notebookIndex].sections[sectionIndex])
                return
            }
            if updateSection(id: id, in: &notebooks[notebookIndex].sectionGroups, transform: transform) {
                return
            }
        }
    }

    private func updateSection(id: String, in groups: inout [SectionGroupNode], transform: (inout SectionNode) -> Void) -> Bool {
        for groupIndex in groups.indices {
            if let sectionIndex = groups[groupIndex].sections.firstIndex(where: { $0.id == id }) {
                transform(&groups[groupIndex].sections[sectionIndex])
                return true
            }
            if updateSection(id: id, in: &groups[groupIndex].sectionGroups, transform: transform) {
                return true
            }
        }
        return false
    }

    private func updateSectionGroup(id: String, transform: (inout SectionGroupNode) -> Void) {
        for notebookIndex in notebooks.indices {
            if updateSectionGroup(id: id, in: &notebooks[notebookIndex].sectionGroups, transform: transform) {
                return
            }
        }
    }

    private func updateSectionGroup(
        id: String,
        in groups: inout [SectionGroupNode],
        transform: (inout SectionGroupNode) -> Void
    ) -> Bool {
        for groupIndex in groups.indices {
            if groups[groupIndex].id == id {
                transform(&groups[groupIndex])
                return true
            }
            if updateSectionGroup(id: id, in: &groups[groupIndex].sectionGroups, transform: transform) {
                return true
            }
        }
        return false
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: "OpenNoteBatch.settings"),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return }
        settings = decoded
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "OpenNoteBatch.settings")
    }
}
