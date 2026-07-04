import Foundation

struct OneNoteRepository {
    let client: GraphClient

    func notebooks() async throws -> [NotebookNode] {
        let notebooks: [GraphNotebook] = try await client.getPaged("/me/onenote/notebooks?$select=id,displayName")
        return notebooks.map { NotebookNode(id: $0.id, displayName: $0.displayName) }
    }

    func sections(notebookID: String? = nil) async throws -> [SectionNode] {
        let path: String
        if let notebookID {
            path = "/me/onenote/notebooks/\(notebookID.urlPathEscaped)/sections?$select=id,displayName"
        } else {
            path = "/me/onenote/sections?$select=id,displayName"
        }
        let sections: [GraphSection] = try await client.getPaged(path)
        return sections.map { SectionNode(id: $0.id, displayName: $0.displayName, notebookID: notebookID) }
    }

    func sectionGroups(notebookID: String) async throws -> [SectionGroupNode] {
        let path = "/me/onenote/notebooks/\(notebookID.urlPathEscaped)/sectionGroups?$select=id,displayName"
        let groups: [GraphSectionGroup] = try await client.getPaged(path)
        return groups.map { SectionGroupNode(id: $0.id, displayName: $0.displayName, notebookID: notebookID) }
    }

    func sections(sectionGroupID: String, notebookID: String? = nil, groupPath: String = "") async throws -> [SectionNode] {
        let path = "/me/onenote/sectionGroups/\(sectionGroupID.urlPathEscaped)/sections?$select=id,displayName"
        let sections: [GraphSection] = try await client.getPaged(path)
        return sections.map {
            SectionNode(id: $0.id, displayName: $0.displayName, notebookID: notebookID, groupPath: groupPath)
        }
    }

    func childSectionGroups(sectionGroupID: String, notebookID: String? = nil, parentPath: String = "") async throws -> [SectionGroupNode] {
        let path = "/me/onenote/sectionGroups/\(sectionGroupID.urlPathEscaped)/sectionGroups?$select=id,displayName"
        let groups: [GraphSectionGroup] = try await client.getPaged(path)
        return groups.map {
            SectionGroupNode(id: $0.id, displayName: $0.displayName, notebookID: notebookID, parentPath: parentPath)
        }
    }

    func pages(sectionID: String) async throws -> [PageNode] {
        let select = "id,title,createdDateTime,lastModifiedDateTime,contentUrl"
        let path = "/me/onenote/sections/\(sectionID.urlPathEscaped)/pages?$top=100&$select=\(select)"
        let pages: [GraphPage] = try await client.getPaged(path)
        return pages.map {
            PageNode(
                id: $0.id,
                title: $0.title ?? "Untitled page",
                createdDateTime: $0.createdDateTime,
                lastModifiedDateTime: $0.lastModifiedDateTime,
                contentURL: $0.contentUrl,
                sectionName: nil
            )
        }
    }

    func pageContent(pageID: String) async throws -> String {
        try await client.getText("/me/onenote/pages/\(pageID.urlPathEscaped)/content?includeIDs=true")
    }

    func attachments(on page: PageNode, includeImages: Bool = false) async throws -> [AttachmentResource] {
        let html = try await pageContent(pageID: page.id)
        var resources = OneNoteHTML.attachments(from: html, page: page)
        if includeImages {
            resources.append(contentsOf: OneNoteHTML.images(from: html, page: page))
        }
        return resources
    }

    func tags(on page: PageNode) async throws -> [BatchResult] {
        let html = try await pageContent(pageID: page.id)
        return OneNoteHTML.tags(from: html, page: page)
    }

    func search(query: String, pages: [PageNode], titleOnly: Bool, matchCase: Bool) async throws -> [BatchResult] {
        guard !query.isEmpty else { return [] }
        var results: [BatchResult] = []
        for page in pages {
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
        }
        return results
    }

    func createPage(sectionID: String, html: String) async throws {
        try await client.postHTML("/me/onenote/sections/\(sectionID.urlPathEscaped)/pages", html: html)
    }

    func renamePage(pageID: String, title: String) async throws {
        try await client.patchJSON("/me/onenote/pages/\(pageID.urlPathEscaped)", body: ["title": title])
    }
}

private struct GraphNotebook: Decodable {
    var id: String
    var displayName: String
}

private struct GraphSection: Decodable {
    var id: String
    var displayName: String
}

private struct GraphSectionGroup: Decodable {
    var id: String
    var displayName: String
}

private struct GraphPage: Decodable {
    var id: String
    var title: String?
    var createdDateTime: Date?
    var lastModifiedDateTime: Date?
    var contentUrl: String?
}

private extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
