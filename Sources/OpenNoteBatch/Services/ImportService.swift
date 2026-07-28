import Foundation
import UniformTypeIdentifiers

struct ImportService {
    let repository: OneNoteRepository
    let client: GraphClient

    @MainActor
    func importText(files: [URL], sectionID: String, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        var results: [BatchResult] = []
        for (index, file) in files.enumerated() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let title = file.deletingPathExtension().lastPathComponent
            try await repository.createPage(sectionID: sectionID, html: OneNoteHTML.textHTML(title: title, text: text))
            results.append(.init(name: file.lastPathComponent, path: file.path, status: .success, message: "Created OneNote page."))
            await progress?(index + 1, files.count, "Imported \(file.lastPathComponent).")
        }
        return results
    }

    @MainActor
    func importHTML(files: [URL], sectionID: String, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        var results: [BatchResult] = []
        for (index, file) in files.enumerated() {
            let html = try String(contentsOf: file, encoding: .utf8)
            let title = OneNoteHTML.title(from: html, fallback: file.deletingPathExtension().lastPathComponent)
            let pageHTML = html.localizedCaseInsensitiveContains("<html") ? html : OneNoteHTML.htmlPage(title: title, body: html)
            try await repository.createPage(sectionID: sectionID, html: pageHTML)
            results.append(.init(name: file.lastPathComponent, path: file.path, status: .success, message: "Created OneNote page."))
            await progress?(index + 1, files.count, "Imported \(file.lastPathComponent).")
        }
        return results
    }

    @MainActor
    func importImages(files: [URL], sectionID: String, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        var results: [BatchResult] = []
        for (index, file) in files.enumerated() {
            let data = try Data(contentsOf: file)
            let title = file.deletingPathExtension().lastPathComponent
            let contentType = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "image/png"
            var multipart = MultipartBuilder()
            multipart.addTextPart(
                name: "Presentation",
                value: OneNoteHTML.htmlPage(title: title, body: "<img src=\"name:image1\" />"),
                contentType: "text/html"
            )
            multipart.addFilePart(name: "image1", filename: file.lastPathComponent, contentType: contentType, data: data)
            try await client.postMultipart("/me/onenote/sections/\(sectionID.urlPathEscaped)/pages", builder: multipart)
            results.append(.init(name: file.lastPathComponent, path: file.path, status: .success, message: "Created image page."))
            await progress?(index + 1, files.count, "Imported \(file.lastPathComponent).")
        }
        return results
    }

    @MainActor
    func importTree(
        root: URL,
        sectionID: String,
        includeText: Bool,
        includeHTML: Bool,
        progress: BatchProgressUpdate? = nil
    ) async throws -> [BatchResult] {
        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { url in
                let ext = url.pathExtension.lowercased()
                return (includeText && ext == "txt") || (includeHTML && ["html", "htm"].contains(ext))
            }
        var results: [BatchResult] = []
        let textFiles = files.filter { $0.pathExtension.lowercased() == "txt" }
        let htmlFiles = files.filter { ["html", "htm"].contains($0.pathExtension.lowercased()) }
        var completed = 0
        results.append(contentsOf: try await importText(files: textFiles, sectionID: sectionID) { _, _, message in
            completed += 1
            await progress?(completed, files.count, message)
        })
        results.append(contentsOf: try await importHTML(files: htmlFiles, sectionID: sectionID) { _, _, message in
            completed += 1
            await progress?(completed, files.count, message)
        })
        return results
    }

    @MainActor
    func importEvernote(file: URL, sectionID: String, progress: BatchProgressUpdate? = nil) async throws -> [BatchResult] {
        let enex = try String(contentsOf: file, encoding: .utf8)
        let notePattern = #"<note>[\s\S]*?</note>"#
        let notes = matches(pattern: notePattern, in: enex)
        var results: [BatchResult] = []
        for (index, note) in notes.enumerated() {
            let title = firstCapture(pattern: #"<title>([\s\S]*?)</title>"#, in: note) ?? "Evernote Note \(index + 1)"
            let content = firstCapture(pattern: #"<content><!\[CDATA\[([\s\S]*?)\]\]></content>"#, in: note) ?? ""
            let html = OneNoteHTML.htmlPage(title: title, body: content)
            try await repository.createPage(sectionID: sectionID, html: html)
            results.append(.init(name: title, path: file.path, status: .success, message: "Imported ENEX note."))
            await progress?(index + 1, notes.count, "Imported \(title).")
        }
        if notes.isEmpty {
            results.append(.init(name: file.lastPathComponent, path: file.path, status: .warning, message: "No ENEX notes found."))
            await progress?(1, 1, "No ENEX notes found.")
        }
        return results
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            guard let matchRange = Range($0.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }
}

private extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
