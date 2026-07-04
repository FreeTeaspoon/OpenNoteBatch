import Foundation

struct ExportService {
    let repository: OneNoteRepository
    let client: GraphClient

    func saveAttachments(pages: [PageNode], outputDirectory: URL, includeImages: Bool) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        for page in pages {
            let pageFolder = outputDirectory.appendingPathComponent(Filename.safe(page.title))
            let attachmentsFolder = pageFolder.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: attachmentsFolder, withIntermediateDirectories: true)
            let resources = try await repository.attachments(on: page, includeImages: includeImages)
            if resources.isEmpty {
                results.append(.init(name: page.title, path: pageFolder.path, status: .warning, message: "No attachments found."))
            }
            for resource in resources {
                let data = try await client.download(resource.resourceURL)
                let target = Filename.unique(in: attachmentsFolder, name: resource.fileName)
                try data.write(to: target)
                results.append(.init(name: resource.fileName, path: target.path, status: .success, message: "Saved from \(page.title)."))
            }
        }
        return results
    }

    func exportText(pages: [PageNode], outputDirectory: URL) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        for page in pages {
            let html = try await repository.pageContent(pageID: page.id)
            let text = OneNoteHTML.plainText(from: html)
            let target = Filename.unique(in: outputDirectory, name: "\(page.title).txt")
            try text.write(to: target, atomically: true, encoding: .utf8)
            results.append(.init(name: page.title, path: target.path, status: .success, message: "Exported plain text."))
        }
        return results
    }

    func exportHTML(pages: [PageNode], outputDirectory: URL) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        for page in pages {
            let html = try await repository.pageContent(pageID: page.id)
            let target = Filename.unique(in: outputDirectory, name: "\(page.title).html")
            try html.write(to: target, atomically: true, encoding: .utf8)
            results.append(.init(name: page.title, path: target.path, status: .success, message: "Exported HTML."))
        }
        return results
    }

    func backup(pages: [PageNode], outputDirectory: URL) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var manifest = BackupManifest(createdAt: Date(), pages: [])
        var results: [BatchResult] = []

        for page in pages {
            let pageDirectory = outputDirectory
                .appendingPathComponent(Filename.safe(page.sectionName ?? "Pages"))
                .appendingPathComponent(Filename.safe(page.title))
            let attachmentDirectory = pageDirectory.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)

            let html = try await repository.pageContent(pageID: page.id)
            let text = OneNoteHTML.plainText(from: html)
            let htmlURL = pageDirectory.appendingPathComponent("page.html")
            let textURL = pageDirectory.appendingPathComponent("page.txt")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            try text.write(to: textURL, atomically: true, encoding: .utf8)

            var attachmentNames: [String] = []
            for resource in OneNoteHTML.attachments(from: html, page: page) {
                let data = try await client.download(resource.resourceURL)
                let target = Filename.unique(in: attachmentDirectory, name: resource.fileName)
                try data.write(to: target)
                attachmentNames.append(target.lastPathComponent)
            }

            manifest.pages.append(.init(
                pageID: page.id,
                title: page.title,
                sectionName: page.sectionName ?? "",
                htmlPath: htmlURL.path,
                textPath: textURL.path,
                attachments: attachmentNames
            ))
            results.append(.init(name: page.title, path: pageDirectory.path, status: .success, message: "Backed up page."))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
        try encoder.encode(manifest).write(to: manifestURL)
        results.append(.init(name: "manifest.json", path: manifestURL.path, status: .success, message: "Backup manifest written."))
        return results
    }
}

struct BackupManifest: Codable, Equatable {
    struct Page: Codable, Equatable {
        var pageID: String
        var title: String
        var sectionName: String
        var htmlPath: String
        var textPath: String
        var attachments: [String]
    }

    var createdAt: Date
    var pages: [Page]
}

