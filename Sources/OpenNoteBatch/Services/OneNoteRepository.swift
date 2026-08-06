import Foundation

struct OneNoteRepository {
    let client: GraphClient

    func notebooks() async throws -> [NotebookNode] {
        let notebooks: [GraphNotebook] = try await client.getPaged(
            "/me/onenote/notebooks?$select=id,displayName,createdDateTime&$orderby=createdDateTime"
        )
        return notebooks.map {
            NotebookNode(id: $0.id, displayName: $0.displayName, createdDateTime: $0.createdDateTime)
        }
    }

    func sections(notebookID: String? = nil) async throws -> [SectionNode] {
        let path: String
        if let notebookID {
            path = "/me/onenote/notebooks/\(notebookID.urlPathEscaped)/sections?$select=id,displayName,createdDateTime&$orderby=createdDateTime"
        } else {
            path = "/me/onenote/sections?$select=id,displayName,createdDateTime&$orderby=createdDateTime"
        }
        let sections: [GraphSection] = try await client.getPaged(path)
        return sections.map {
            SectionNode(
                id: $0.id,
                displayName: $0.displayName,
                notebookID: notebookID,
                createdDateTime: $0.createdDateTime
            )
        }
    }

    func sectionGroups(notebookID: String) async throws -> [SectionGroupNode] {
        let path = "/me/onenote/notebooks/\(notebookID.urlPathEscaped)/sectionGroups?$select=id,displayName,createdDateTime&$orderby=createdDateTime"
        let groups: [GraphSectionGroup] = try await client.getPaged(path)
        return groups.map {
            SectionGroupNode(
                id: $0.id,
                displayName: $0.displayName,
                notebookID: notebookID,
                createdDateTime: $0.createdDateTime
            )
        }
    }

    func sections(sectionGroupID: String, notebookID: String? = nil, groupPath: String = "") async throws -> [SectionNode] {
        let path = "/me/onenote/sectionGroups/\(sectionGroupID.urlPathEscaped)/sections?$select=id,displayName,createdDateTime&$orderby=createdDateTime"
        let sections: [GraphSection] = try await client.getPaged(path)
        return sections.map {
            SectionNode(
                id: $0.id,
                displayName: $0.displayName,
                notebookID: notebookID,
                createdDateTime: $0.createdDateTime,
                groupPath: groupPath
            )
        }
    }

    func childSectionGroups(sectionGroupID: String, notebookID: String? = nil, parentPath: String = "") async throws -> [SectionGroupNode] {
        let path = "/me/onenote/sectionGroups/\(sectionGroupID.urlPathEscaped)/sectionGroups?$select=id,displayName,createdDateTime&$orderby=createdDateTime"
        let groups: [GraphSectionGroup] = try await client.getPaged(path)
        return groups.map {
            SectionGroupNode(
                id: $0.id,
                displayName: $0.displayName,
                notebookID: notebookID,
                createdDateTime: $0.createdDateTime,
                parentPath: parentPath
            )
        }
    }

    func pages(sectionID: String) async throws -> [PageNode] {
        let select = "id,title,createdDateTime,lastModifiedDateTime,contentUrl,level,order"
        let path = "/me/onenote/sections/\(sectionID.urlPathEscaped)/pages?pagelevel=true&$top=100&$select=\(select)"
        let pages: [GraphPage] = try await client.getPaged(path)
        return OneNoteOrdering.pages(pages.map {
            PageNode(
                id: $0.id,
                title: $0.title ?? "Untitled page",
                createdDateTime: $0.createdDateTime,
                lastModifiedDateTime: $0.lastModifiedDateTime,
                contentURL: $0.contentUrl,
                sectionName: nil,
                level: $0.level,
                order: $0.order
            )
        })
    }

    func pageContent(pageID: String) async throws -> String {
        try await client.getText("/me/onenote/pages/\(pageID.urlPathEscaped)/content?includeIDs=true")
    }

    func pageContent(pageID: String, includeInkML: Bool) async throws -> OneNotePageContent {
        let query = includeInkML ? "includeIDs=true&includeInkML=true" : "includeIDs=true"
        let serviceRoot = includeInkML
            ? client.root.replacingOccurrences(of: "/v1.0", with: "/beta")
            : client.root
        return try await client.getPageContent(
            "\(serviceRoot)/me/onenote/pages/\(pageID.urlPathEscaped)/content?\(query)",
            includeInkML: includeInkML
        )
    }

    func attachments(on page: PageNode) async throws -> [AttachmentResource] {
        let html = try await pageContent(pageID: page.id)
        return OneNoteHTML.attachments(from: html, page: page)
    }

    func tags(on page: PageNode) async throws -> [BatchResult] {
        let html = try await pageContent(pageID: page.id)
        return OneNoteHTML.tags(from: html, page: page)
    }

    @MainActor
    func search(
        query: String,
        pages: [PageNode],
        titleOnly: Bool,
        matchCase: Bool,
        progress: BatchProgressUpdate? = nil
    ) async throws -> [BatchResult] {
        guard !query.isEmpty else { return [] }
        var results: [BatchResult] = []
        for (index, page) in pages.enumerated() {
            let haystack: String
            if titleOnly {
                haystack = page.title
            } else {
                let html = try await pageContent(pageID: page.id)
                haystack = page.title + "\n" + OneNoteHTML.plainText(from: html)
            }
            let source = matchCase ? haystack : haystack.lowercased()
            let needle = matchCase ? query : query.lowercased()
            if source.contains(needle) {
                results.append(.init(name: page.title, path: page.sectionName ?? "", status: .success, message: "Matched search text."))
            }
            await progress?(index + 1, pages.count, "Searched \(page.title).")
        }
        return results
    }

    func createPage(sectionID: String, html: String) async throws {
        try await client.postHTML("/me/onenote/sections/\(sectionID.urlPathEscaped)/pages", html: html)
    }

    func renamePage(pageID: String, title: String) async throws {
        try await client.patchJSON("/me/onenote/pages/\(pageID.urlPathEscaped)", body: ["title": title])
    }

    func renameNotebook(notebookID: String, displayName: String) async throws {
        try await client.patchJSON("/me/onenote/notebooks/\(notebookID.urlPathEscaped)", body: ["displayName": displayName])
    }

    func renameSectionGroup(sectionGroupID: String, displayName: String) async throws {
        try await client.patchJSON("/me/onenote/sectionGroups/\(sectionGroupID.urlPathEscaped)", body: ["displayName": displayName])
    }

    func renameSection(sectionID: String, displayName: String) async throws {
        try await client.patchJSON("/me/onenote/sections/\(sectionID.urlPathEscaped)", body: ["displayName": displayName])
    }
}

private struct GraphNotebook: Decodable {
    var id: String
    var displayName: String
    var createdDateTime: Date?
}

private struct GraphSection: Decodable {
    var id: String
    var displayName: String
    var createdDateTime: Date?
}

private struct GraphSectionGroup: Decodable {
    var id: String
    var displayName: String
    var createdDateTime: Date?
}

private struct GraphPage: Decodable {
    var id: String
    var title: String?
    var createdDateTime: Date?
    var lastModifiedDateTime: Date?
    var contentUrl: String?
    var level: Int?
    var order: Int?
}

private extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
