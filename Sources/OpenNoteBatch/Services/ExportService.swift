import Foundation

typealias BatchProgressUpdate = (Int, Int, String) async -> Void

struct ExportService {
    let repository: OneNoteRepository
    let client: GraphClient

    @MainActor
    func exportAttachmentsAndImages(
        pages: [PageNode],
        outputDirectory: URL,
        includeAttachments: Bool,
        includeImages: Bool,
        includeDrawings: Bool,
        createPDF: Bool,
        progress: BatchProgressUpdate? = nil
    ) async throws -> [BatchResult] {
        guard includeAttachments || includeImages else {
            throw OpenNoteError.selectionRequired("Choose file attachments, embedded images, or both to export.")
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        var completed = 0
        var total = max(pages.count, 1)
        var fileNamer = ExportFileNamer()

        for page in pages {
            let pageDirectory = ExportPath.pageDirectory(for: page, outputDirectory: outputDirectory)
            let attachmentsDirectory = pageDirectory.appendingPathComponent("attachments")

            let fetchedContent: (content: OneNotePageContent, drawingFetchWarning: String?)
            do {
                fetchedContent = try await fetchPageContent(
                    for: page,
                    includeDrawings: includeImages && includeDrawings
                )
            } catch {
                if includeAttachments {
                    results.append(.init(
                        name: page.title,
                        path: pageDirectory.path,
                        status: .failed,
                        message: "Page resources could not be refreshed: \(error.localizedDescription)"
                    ))
                }
                if includeImages {
                    results.append(.init(
                        name: page.title,
                        path: pageDirectory.path,
                        status: .failed,
                        message: "Page images could not be refreshed: \(error.localizedDescription)"
                    ))
                }
                completed += 1
                await progress?(completed, total, "Skipped unavailable \(page.title).")
                continue
            }

            let attachments = includeAttachments
                ? OneNoteHTML.attachments(from: fetchedContent.content.html, page: page)
                : []
            let images = includeImages
                ? OneNoteHTML.images(from: fetchedContent.content.html, page: page)
                : []
            let strokes = includeImages && includeDrawings
                ? InkMLParser.strokes(from: fetchedContent.content.inkML)
                : []
            total += attachments.count
                + images.count
                + (includeImages && createPDF && !images.isEmpty ? 1 : 0)
            completed += 1
            var discovered: [String] = []
            if includeAttachments {
                discovered.append("\(attachments.count) attachment(s)")
            }
            if includeImages {
                discovered.append("\(images.count) image(s)")
            }
            await progress?(completed, total, "Found \(discovered.joined(separator: " and ")) on \(page.title).")

            if includeAttachments {
                if attachments.isEmpty {
                    results.append(.init(
                        name: page.title,
                        path: pageDirectory.path,
                        status: .warning,
                        message: "No attachments found."
                    ))
                }

                for resource in attachments {
                    do {
                        let data: Data
                        do {
                            data = try await download(resource)
                        } catch {
                            let refreshed = try await repository.attachments(on: page)
                            guard let replacement = refreshed.first(where: {
                                $0.kind == resource.kind && $0.fileName == resource.fileName
                            }) else { throw error }
                            data = try await download(replacement)
                        }
                        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
                        let target = fileNamer.next(in: attachmentsDirectory, name: resource.fileName)
                        try data.write(to: target, options: .atomic)
                        results.append(.init(
                            name: resource.fileName,
                            path: target.path,
                            status: .success,
                            message: "Saved from \(page.title)."
                        ))
                        completed += 1
                        await progress?(completed, total, "Downloaded \(resource.fileName).")
                    } catch {
                        results.append(.init(
                            name: resource.fileName,
                            path: page.title,
                            status: .failed,
                            message: "Resource could not be refreshed: \(error.localizedDescription)"
                        ))
                        completed += 1
                        await progress?(completed, total, "Skipped unavailable \(resource.fileName).")
                    }
                }
            }

            if includeImages {
                if images.isEmpty {
                    results.append(.init(
                        name: page.title,
                        path: "",
                        status: .warning,
                        message: "No embedded images found."
                    ))
                } else {
                    try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
                    var renderedImages: [Data] = []

                    for (imageIndex, resource) in images.enumerated() {
                        let downloaded: Data
                        let currentResource: AttachmentResource
                        do {
                            do {
                                downloaded = try await downloadRenderableImage(resource)
                                currentResource = resource
                            } catch {
                                let refreshedContent = try await repository.pageContent(pageID: page.id, includeInkML: false)
                                let refreshedImages = OneNoteHTML.images(from: refreshedContent.html, page: page)
                                guard refreshedImages.indices.contains(imageIndex) else { throw error }
                                currentResource = refreshedImages[imageIndex]
                                downloaded = try await downloadRenderableImage(currentResource)
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
                        let target = fileNamer.next(
                            in: pageDirectory,
                            name: "\(stem).\(rendered.fileExtension)"
                        )
                        try rendered.data.write(to: target, options: .atomic)
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
                        let pdfTarget = fileNamer.next(
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
                }
            }

            if includeImages, !images.isEmpty, let drawingFetchWarning = fetchedContent.drawingFetchWarning {
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

    @MainActor
    private func fetchPageContent(
        for page: PageNode,
        includeDrawings: Bool
    ) async throws -> (content: OneNotePageContent, drawingFetchWarning: String?) {
        guard includeDrawings else {
            return (try await repository.pageContent(pageID: page.id, includeInkML: false), nil)
        }

        do {
            return (try await repository.pageContent(pageID: page.id, includeInkML: true), nil)
        } catch {
            let content = try await repository.pageContent(pageID: page.id, includeInkML: false)
            return (
                content,
                "Images were exported, but Microsoft Graph did not return drawing data: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    func exportText(pages: [PageNode], outputDirectory: URL, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var results: [BatchResult] = []
        var fileNamer = ExportFileNamer()
        for (index, page) in pages.enumerated() {
            do {
                let html = try await repository.pageContent(pageID: page.id)
                let text = OneNoteHTML.plainText(from: html)
                let pageDirectory = ExportPath.pageDirectory(for: page, outputDirectory: outputDirectory)
                try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
                let target = fileNamer.next(in: pageDirectory, name: "\(page.title).txt")
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
        var fileNamer = ExportFileNamer()
        for (index, page) in pages.enumerated() {
            do {
                let html = try await repository.pageContent(pageID: page.id)
                let pageDirectory = ExportPath.pageDirectory(for: page, outputDirectory: outputDirectory)
                try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
                let target = fileNamer.next(in: pageDirectory, name: "\(page.title).html")
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

    private func download(_ resource: AttachmentResource) async throws -> Data {
        do {
            return try await client.download(resource.resourceURL)
        } catch {
            guard let alternate = resource.alternateResourceURL else { throw error }
            return try await client.download(alternate)
        }
    }

    @MainActor
    private func downloadRenderableImage(_ resource: AttachmentResource) async throws -> Data {
        let data = try await download(resource)
        guard !ImageExportRenderer.isSupportedImageData(data) else { return data }

        guard let alternate = resource.alternateResourceURL else {
            throw OpenNoteError.fileSystem(
                "OneNote returned an unsupported image format for \(resource.fileName)."
            )
        }
        let alternateData = try await client.download(alternate)
        guard ImageExportRenderer.isSupportedImageData(alternateData) else {
            throw OpenNoteError.fileSystem(
                "OneNote returned unsupported image data for \(resource.fileName)."
            )
        }
        return alternateData
    }

    @MainActor
    func backup(pages: [PageNode], outputDirectory: URL, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var manifest = BackupManifest(createdAt: Date(), pages: [])
        var results: [BatchResult] = []
        var completedPages = 0
        var discoveredAttachments = 0
        var downloadedAttachments = 0
        var fileNamer = ExportFileNamer()

        for page in pages {
            let pageDirectory = ExportPath.pageDirectory(for: page, outputDirectory: outputDirectory)
            let attachmentDirectory = pageDirectory.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)

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
                    try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
                    let target = fileNamer.next(in: attachmentDirectory, name: resource.fileName)
                    try data.write(to: target, options: .atomic)
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
