import Foundation

typealias BatchProgressUpdate = (Int, Int, String) async -> Void

struct ExportService {
    let repository: OneNoteRepository
    let client: GraphClient

    @MainActor
    func saveAttachments(
        pages: [PageNode],
        outputDirectory: URL,
        includeImages: Bool,
        progress: BatchProgressUpdate? = nil
    ) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        var scannedPages = 0
        var discoveredResources = 0
        var downloadedResources = 0
        for page in pages {
            let pageFolder = outputDirectory.appendingPathComponent(Filename.safe(page.title))
            let attachmentsFolder = pageFolder.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: attachmentsFolder, withIntermediateDirectories: true)
            scannedPages += 1
            let resources: [AttachmentResource]
            do {
                resources = try await repository.attachments(on: page, includeImages: includeImages)
            } catch {
                results.append(.init(
                    name: page.title,
                    path: pageFolder.path,
                    status: .failed,
                    message: "Page resources could not be refreshed: \(error.localizedDescription)"
                ))
                await progress?(scannedPages + downloadedResources, pages.count + discoveredResources, "Skipped unavailable \(page.title).")
                continue
            }
            discoveredResources += resources.count
            if resources.isEmpty {
                results.append(.init(name: page.title, path: pageFolder.path, status: .warning, message: "No attachments found."))
                await progress?(scannedPages + downloadedResources, pages.count + discoveredResources, "Scanned \(page.title).")
            }
            for resource in resources {
                downloadedResources += 1
                do {
                    let data: Data
                    do {
                        data = try await download(resource)
                    } catch {
                        let refreshed = try await repository.attachments(on: page, includeImages: includeImages)
                        guard let replacement = refreshed.first(where: {
                            $0.kind == resource.kind && $0.fileName == resource.fileName
                        }) else { throw error }
                        data = try await download(replacement)
                    }
                    let target = Filename.unique(in: attachmentsFolder, name: resource.fileName)
                    try data.write(to: target)
                    results.append(.init(name: resource.fileName, path: target.path, status: .success, message: "Saved from \(page.title)."))
                    await progress?(scannedPages + downloadedResources, pages.count + discoveredResources, "Downloaded \(resource.fileName).")
                } catch {
                    results.append(.init(
                        name: resource.fileName,
                        path: page.title,
                        status: .failed,
                        message: "Resource could not be refreshed: \(error.localizedDescription)"
                    ))
                    await progress?(scannedPages + downloadedResources, pages.count + discoveredResources, "Skipped unavailable \(resource.fileName).")
                }
            }
        }
        return results
    }

    @MainActor
    func exportText(pages: [PageNode], outputDirectory: URL, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        for (index, page) in pages.enumerated() {
            do {
                let html = try await repository.pageContent(pageID: page.id)
                let text = OneNoteHTML.plainText(from: html)
                let target = Filename.unique(in: outputDirectory, name: "\(page.title).txt")
                try text.write(to: target, atomically: true, encoding: .utf8)
                results.append(.init(name: page.title, path: target.path, status: .success, message: "Exported plain text."))
                await progress?(index + 1, pages.count, "Exported \(page.title).")
            } catch {
                results.append(.init(name: page.title, path: "", status: .failed, message: error.localizedDescription))
                await progress?(index + 1, pages.count, "Skipped unavailable \(page.title).")
            }
        }
        return results
    }

    @MainActor
    func exportHTML(pages: [PageNode], outputDirectory: URL, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        for (index, page) in pages.enumerated() {
            do {
                let html = try await repository.pageContent(pageID: page.id)
                let target = Filename.unique(in: outputDirectory, name: "\(page.title).html")
                try html.write(to: target, atomically: true, encoding: .utf8)
                results.append(.init(name: page.title, path: target.path, status: .success, message: "Exported HTML."))
                await progress?(index + 1, pages.count, "Exported \(page.title).")
            } catch {
                results.append(.init(name: page.title, path: "", status: .failed, message: error.localizedDescription))
                await progress?(index + 1, pages.count, "Skipped unavailable \(page.title).")
            }
        }
        return results
    }

    @MainActor
    func exportImages(
        pages: [PageNode],
        outputDirectory: URL,
        includeDrawings: Bool,
        createPDF: Bool,
        progress: BatchProgressUpdate? = nil
    ) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        var completed = 0
        var total = pages.count

        for page in pages {
            let content: OneNotePageContent
            var drawingFetchWarning: String?
            if includeDrawings {
                do {
                    content = try await repository.pageContent(pageID: page.id, includeInkML: true)
                } catch {
                    content = try await repository.pageContent(pageID: page.id, includeInkML: false)
                    drawingFetchWarning = "Images were exported, but Microsoft Graph did not return drawing data: \(error.localizedDescription)"
                }
            } else {
                content = try await repository.pageContent(pageID: page.id, includeInkML: false)
            }
            let images = OneNoteHTML.images(from: content.html, page: page)
            let strokes = includeDrawings ? InkMLParser.strokes(from: content.inkML) : []
            total += images.count + (createPDF && !images.isEmpty ? 1 : 0)
            completed += 1
            await progress?(completed, total, "Found \(images.count) image(s) on \(page.title).")

            guard !images.isEmpty else {
                results.append(.init(
                    name: page.title,
                    path: "",
                    status: .warning,
                    message: "No embedded images found."
                ))
                continue
            }

            let pageDirectory = outputDirectory.appendingPathComponent(Filename.safe(page.title))
            try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
            var renderedImages: [Data] = []

            for (imageIndex, resource) in images.enumerated() {
                let downloaded: Data
                let currentResource: AttachmentResource
                do {
                    do {
                        downloaded = try await download(resource)
                        currentResource = resource
                    } catch {
                        let refreshedContent = try await repository.pageContent(pageID: page.id, includeInkML: false)
                        let refreshedImages = OneNoteHTML.images(from: refreshedContent.html, page: page)
                        guard refreshedImages.indices.contains(imageIndex) else { throw error }
                        currentResource = refreshedImages[imageIndex]
                        downloaded = try await download(currentResource)
                    }
                } catch {
                    completed += 1
                    results.append(.init(
                        name: resource.fileName,
                        path: page.title,
                        status: .failed,
                        message: "Image resource no longer exists and could not be refreshed: \(error.localizedDescription)"
                    ))
                    await progress?(completed, total, "Skipped unavailable \(resource.fileName).")
                    continue
                }

                let rendered = try ImageExportRenderer.render(
                    imageData: downloaded,
                    resource: currentResource,
                    strokes: strokes
                )
                renderedImages.append(rendered.data)
                let stem = URL(fileURLWithPath: resource.fileName).deletingPathExtension().lastPathComponent
                let target = Filename.unique(
                    in: pageDirectory,
                    name: "\(stem).\(rendered.fileExtension)"
                )
                try rendered.data.write(to: target)
                let drawingMessage = rendered.includedDrawings
                    ? "Saved in page order with overlapping drawings."
                    : includeDrawings
                        ? (strokes.isEmpty
                            ? "Saved in visual page order; no drawing data was returned."
                            : "Saved in visual page order; no drawings overlapped this image.")
                        : "Saved in visual page order."
                results.append(.init(
                    name: target.lastPathComponent,
                    path: target.path,
                    status: .success,
                    message: drawingMessage
                ))
                completed += 1
                await progress?(completed, total, "Exported \(target.lastPathComponent).")
            }

            if createPDF, !renderedImages.isEmpty {
                let pdfTarget = Filename.unique(
                    in: pageDirectory,
                    name: "\(Filename.safe(page.title)).pdf"
                )
                try ImageExportRenderer.writePDF(images: renderedImages, to: pdfTarget)
                results.append(.init(
                    name: pdfTarget.lastPathComponent,
                    path: pdfTarget.path,
                    status: .success,
                    message: "Created PDF with \(renderedImages.count) image page(s) in visual order."
                ))
                completed += 1
                await progress?(completed, total, "Created \(pdfTarget.lastPathComponent).")
            } else if createPDF {
                completed += 1
                results.append(.init(
                    name: page.title,
                    path: pageDirectory.path,
                    status: .warning,
                    message: "PDF was not created because no image resources were available."
                ))
                await progress?(completed, total, "Skipped PDF for \(page.title).")
            }

            if let drawingFetchWarning {
                results.append(.init(
                    name: page.title,
                    path: pageDirectory.path,
                    status: .warning,
                    message: drawingFetchWarning
                ))
            }
        }
        return results
    }

    private func download(_ resource: AttachmentResource) async throws -> Data {
        do {
            return try await client.download(resource.resourceURL)
        } catch {
            guard let alternate = resource.alternateResourceURL else { throw error }
            return try await client.download(alternate)
        }
    }

    @MainActor
    func backup(pages: [PageNode], outputDirectory: URL, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var manifest = BackupManifest(createdAt: Date(), pages: [])
        var results: [BatchResult] = []
        var completedPages = 0
        var discoveredAttachments = 0
        var downloadedAttachments = 0

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
            let resources = OneNoteHTML.attachments(from: html, page: page)
            discoveredAttachments += resources.count
            var unavailableAttachments = 0
            for resource in resources {
                downloadedAttachments += 1
                do {
                    let data = try await download(resource)
                    let target = Filename.unique(in: attachmentDirectory, name: resource.fileName)
                    try data.write(to: target)
                    attachmentNames.append(target.lastPathComponent)
                    await progress?(
                        completedPages + downloadedAttachments,
                        pages.count + discoveredAttachments + 1,
                        "Downloaded \(resource.fileName)."
                    )
                } catch {
                    unavailableAttachments += 1
                    results.append(.init(
                        name: resource.fileName,
                        path: page.title,
                        status: .failed,
                        message: "Attachment resource is no longer available: \(error.localizedDescription)"
                    ))
                    await progress?(
                        completedPages + downloadedAttachments,
                        pages.count + discoveredAttachments + 1,
                        "Skipped unavailable \(resource.fileName)."
                    )
                }
            }

            manifest.pages.append(.init(
                pageID: page.id,
                title: page.title,
                sectionName: page.sectionName ?? "",
                htmlPath: htmlURL.path,
                textPath: textURL.path,
                attachments: attachmentNames
            ))
            results.append(.init(
                name: page.title,
                path: pageDirectory.path,
                status: unavailableAttachments == 0 ? .success : .warning,
                message: unavailableAttachments == 0
                    ? "Backed up page."
                    : "Backed up page with \(unavailableAttachments) unavailable attachment(s)."
            ))
            completedPages += 1
            await progress?(completedPages + downloadedAttachments, pages.count + discoveredAttachments + 1, "Backed up \(page.title).")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
        try encoder.encode(manifest).write(to: manifestURL)
        results.append(.init(name: "manifest.json", path: manifestURL.path, status: .success, message: "Backup manifest written."))
        await progress?(pages.count + downloadedAttachments + 1, pages.count + discoveredAttachments + 1, "Wrote backup manifest.")
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
