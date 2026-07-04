import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings = AppSettings() {
        didSet { saveSettings() }
    }
    @Published var selectedTab: WorkspaceTab = .home
    @Published var selectedToolID: ToolID = .attachmentList
    @Published var notebooks: [NotebookNode] = []
    @Published var selectedPageIDs: Set<String> = []
    @Published var selectedSectionID: String?
    @Published var targetSectionID = ""
    @Published var outputDirectory: URL?
    @Published var importFiles: [URL] = []
    @Published var importRoot: URL?
    @Published var includeImages = false
    @Published var matchCase = false
    @Published var titleOnlySearch = true
    @Published var searchText = ""
    @Published var replaceText = ""
    @Published var task = BatchTask(title: "Ready", progress: 0, status: .ready)
    @Published var results: [BatchResult] = []
    @Published var isBusy = false
    @Published var statusMessage = "Sign in, load notebooks, then choose a tool."
    @Published var showSettings = false

    let auth = AuthService()
    private var cancellables = Set<AnyCancellable>()

    var selectedTool: ToolDefinition {
        ToolDefinition.all.first { $0.id == selectedToolID } ?? ToolDefinition.all[0]
    }

    var visibleTools: [ToolDefinition] {
        ToolDefinition.all.filter { $0.tab == selectedTab }
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
    }

    func select(tab: WorkspaceTab) {
        selectedTab = tab
        selectedToolID = ToolDefinition.all.first { $0.tab == tab }?.id ?? .attachmentList
        results = []
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
                let repository = try await self.makeRepository()
                var loadedNotebooks = try await repository.notebooks()
                for notebookIndex in loadedNotebooks.indices {
                    var sections = try await repository.sections(notebookID: loadedNotebooks[notebookIndex].id)
                    sections = try await self.loadPages(
                        for: sections,
                        repository: repository,
                        notebookName: loadedNotebooks[notebookIndex].displayName
                    )
                    loadedNotebooks[notebookIndex].sections = sections
                    loadedNotebooks[notebookIndex].sectionGroups = try await self.loadSectionGroups(
                        notebookID: loadedNotebooks[notebookIndex].id,
                        notebookName: loadedNotebooks[notebookIndex].displayName,
                        repository: repository
                    )
                }
                self.notebooks = loadedNotebooks
                self.statusMessage = "Loaded \(loadedNotebooks.count) notebook(s)."
                return [.init(name: "Notebook tree", path: "", status: .success, message: "Loaded notebooks, sections, and pages.")]
            }
        }
    }

    func togglePage(_ page: PageNode, isSelected: Bool) {
        if isSelected {
            selectedPageIDs.insert(page.id)
        } else {
            selectedPageIDs.remove(page.id)
        }
    }

    func toggleSection(_ section: SectionNode, isSelected: Bool) {
        selectedSectionID = section.id
        for page in section.pages {
            togglePage(page, isSelected: isSelected)
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

                switch self.selectedToolID {
                case .attachmentList:
                    return try await self.runAttachmentList(exportService: exportService)
                case .tagList:
                    return try await self.runTagList(repository: repository)
                case .replacePageTitle:
                    return try await self.runReplacePageTitle(repository: repository)
                case .search:
                    return try await self.runSearch(repository: repository)
                case .findLost, .sectionSize:
                    return runner.unsupported(self.selectedTool)
                case .copySections:
                    return try await self.runCopySections(repository: repository)
                case .exportText:
                    return try await exportService.exportText(pages: self.requiredPages(), outputDirectory: self.resolvedOutputDirectory())
                case .exportHTML:
                    return try await exportService.exportHTML(pages: self.requiredPages(), outputDirectory: self.resolvedOutputDirectory())
                case .backup:
                    return try await exportService.backup(pages: self.requiredPages(), outputDirectory: self.resolvedOutputDirectory())
                case .importText:
                    return try await importService.importText(files: self.requiredImportFiles(), sectionID: self.requiredTargetSection())
                case .importHTML, .importMacNotes, .importGoogleKeep:
                    return try await importService.importHTML(files: self.requiredImportFiles(), sectionID: self.requiredTargetSection())
                case .importImages:
                    return try await importService.importImages(files: self.requiredImportFiles(), sectionID: self.requiredTargetSection())
                case .importTree:
                    guard let importRoot = self.importRoot else { throw OpenNoteError.selectionRequired("Choose a source folder first.") }
                    return try await importService.importTree(root: importRoot, sectionID: self.requiredTargetSection(), includeText: true, includeHTML: true)
                case .importEvernote:
                    guard let file = try self.requiredImportFiles().first else { throw OpenNoteError.selectionRequired("Choose an ENEX file first.") }
                    return try await importService.importEvernote(file: file, sectionID: self.requiredTargetSection())
                case .restore:
                    return try await self.runRestore(importService: importService)
                case .account:
                    return self.accountResults()
                }
            }
        }
    }

    private func runBusy(title: String, work: @escaping () async throws -> [BatchResult]) async {
        isBusy = true
        task = BatchTask(title: title, progress: 0.25, status: .running)
        results = []
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

    private func runAttachmentList(exportService: ExportService) async throws -> [BatchResult] {
        let pages = try requiredPages()
        if outputDirectory == nil {
            var listing: [BatchResult] = []
            let repository = exportService.repository
            for page in pages {
                let resources = try await repository.attachments(on: page, includeImages: includeImages)
                listing.append(contentsOf: resources.map {
                    BatchResult(name: $0.fileName, path: page.title, status: .ready, message: "Ready to save.")
                })
                if resources.isEmpty {
                    listing.append(.init(name: page.title, path: "", status: .warning, message: "No attachments found."))
                }
            }
            return listing
        }
        return try await exportService.saveAttachments(pages: pages, outputDirectory: resolvedOutputDirectory(), includeImages: includeImages)
    }

    private func runTagList(repository: OneNoteRepository) async throws -> [BatchResult] {
        var output: [BatchResult] = []
        for page in try requiredPages() {
            let tags = try await repository.tags(on: page)
            output.append(contentsOf: tags)
            if tags.isEmpty {
                output.append(.init(name: page.title, path: page.sectionName ?? "", status: .warning, message: "No tags found."))
            }
        }
        return output
    }

    private func runSearch(repository: OneNoteRepository) async throws -> [BatchResult] {
        let pages = selectedPages.isEmpty ? allPages : selectedPages
        guard !pages.isEmpty else { throw OpenNoteError.selectionRequired("Load notebooks and select pages, or search all loaded pages.") }
        return try await repository.search(query: searchText, pages: pages, titleOnly: titleOnlySearch, matchCase: matchCase)
    }

    private func runReplacePageTitle(repository: OneNoteRepository) async throws -> [BatchResult] {
        guard !searchText.isEmpty else { throw OpenNoteError.selectionRequired("Enter text to find in page titles.") }
        let pages = try requiredPages()
        var output: [BatchResult] = []
        for page in pages {
            let source = matchCase ? page.title : page.title.lowercased()
            let needle = matchCase ? searchText : searchText.lowercased()
            guard source.contains(needle) else { continue }
            let newTitle = matchCase
                ? page.title.replacingOccurrences(of: searchText, with: replaceText)
                : page.title.replacingOccurrences(of: searchText, with: replaceText, options: .caseInsensitive)
            try await repository.renamePage(pageID: page.id, title: newTitle)
            output.append(.init(name: page.title, path: newTitle, status: .success, message: "Renamed page."))
        }
        return output.isEmpty ? [.init(name: "Replace Page Title", path: "", status: .warning, message: "No selected page titles matched.")] : output
    }

    private func runCopySections(repository: OneNoteRepository) async throws -> [BatchResult] {
        let target = try requiredTargetSection()
        var output: [BatchResult] = []
        for page in try requiredPages() {
            let html = try await repository.pageContent(pageID: page.id)
            try await repository.createPage(sectionID: target, html: html)
            output.append(.init(name: page.title, path: target, status: .success, message: "Copied page HTML into target section."))
        }
        return output
    }

    private func runRestore(importService: ImportService) async throws -> [BatchResult] {
        guard let manifestFile = importFiles.first else {
            throw OpenNoteError.selectionRequired("Choose a manifest.json file first.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestFile))
        let htmlFiles = manifest.pages.map { URL(fileURLWithPath: $0.htmlPath) }
        return try await importService.importHTML(files: htmlFiles, sectionID: requiredTargetSection())
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

    private func loadSectionGroups(
        notebookID: String,
        notebookName: String,
        repository: OneNoteRepository
    ) async throws -> [SectionGroupNode] {
        var groups = try await repository.sectionGroups(notebookID: notebookID)
        for index in groups.indices {
            groups[index] = try await loadSectionGroup(
                groups[index],
                notebookName: notebookName,
                repository: repository
            )
        }
        return groups
    }

    private func loadSectionGroup(
        _ group: SectionGroupNode,
        notebookName: String,
        repository: OneNoteRepository
    ) async throws -> SectionGroupNode {
        var loaded = group
        let path = [group.parentPath, group.displayName].filter { !$0.isEmpty }.joined(separator: " / ")
        let sections = try await repository.sections(
            sectionGroupID: group.id,
            notebookID: group.notebookID,
            groupPath: path
        )
        loaded.sections = try await loadPages(
            for: sections,
            repository: repository,
            notebookName: notebookName
        )

        var childGroups = try await repository.childSectionGroups(
            sectionGroupID: group.id,
            notebookID: group.notebookID,
            parentPath: path
        )
        for index in childGroups.indices {
            childGroups[index] = try await loadSectionGroup(
                childGroups[index],
                notebookName: notebookName,
                repository: repository
            )
        }
        loaded.sectionGroups = childGroups
        return loaded
    }

    private func loadPages(
        for sections: [SectionNode],
        repository: OneNoteRepository,
        notebookName: String
    ) async throws -> [SectionNode] {
        var loadedSections = sections
        for sectionIndex in loadedSections.indices {
            var pages = try await repository.pages(sectionID: loadedSections[sectionIndex].id)
            pages = pages.map {
                var page = $0
                page.notebookName = notebookName
                page.sectionName = [loadedSections[sectionIndex].groupPath, loadedSections[sectionIndex].displayName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " / ")
                return page
            }
            loadedSections[sectionIndex].pages = pages
        }
        return loadedSections
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
