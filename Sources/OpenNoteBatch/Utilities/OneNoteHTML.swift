import Foundation

enum OneNoteHTML {
    static func attachments(from html: String, page: PageNode) -> [AttachmentResource] {
        let pattern = #"<object\b[^>]*>"#
        return tags(matching: pattern, in: html).compactMap { tag in
            guard
                let data = attribute("data", in: tag),
                let url = URL(string: data),
                let fileName = attribute("data-attachment", in: tag)
            else { return nil }
            return AttachmentResource(
                fileName: fileName,
                resourceURL: url,
                mediaType: attribute("type", in: tag),
                pageTitle: page.title,
                pageID: page.id,
                kind: "attachment"
            )
        }
    }

    static func images(from html: String, page: PageNode) -> [AttachmentResource] {
        let pattern = #"<img\b[^>]*>"#
        var index = 0
        return tags(matching: pattern, in: html).compactMap { tag in
            let rawURL = attribute("data-fullres-src", in: tag) ?? attribute("src", in: tag)
            guard
                let rawURL,
                rawURL.contains("/onenote/resources/"),
                let url = URL(string: rawURL)
            else { return nil }
            index += 1
            let mediaType = attribute("data-fullres-src-type", in: tag) ?? attribute("data-src-type", in: tag)
            let ext = fileExtension(for: mediaType)
            return AttachmentResource(
                fileName: "image-\(String(format: "%03d", index)).\(ext)",
                resourceURL: url,
                mediaType: mediaType,
                pageTitle: page.title,
                pageID: page.id,
                kind: "image"
            )
        }
    }

    static func tags(from html: String, page: PageNode) -> [BatchResult] {
        let pattern = #"<(span|p|div|li)\b[^>]*data-tag\s*=\s*['"][^'"]+['"][^>]*>"#
        return tags(matching: pattern, in: html).map { tag in
            let tagName = attribute("data-tag", in: tag) ?? "tag"
            return BatchResult(name: tagName, path: page.title, status: .success, message: "Found tag on page.")
        }
    }

    static func plainText(from html: String) -> String {
        var text = html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"</p\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeEntities(text)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func title(from html: String, fallback: String) -> String {
        guard let match = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return fallback
        }
        let raw = String(html[match])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func htmlPage(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>\(escape(title))</title></head>
        <body>\(body)</body>
        </html>
        """
    }

    static func textHTML(title: String, text: String) -> String {
        let body = escape(text).replacingOccurrences(of: "\n", with: "<br />")
        return htmlPage(title: title, body: "<p>\(body)</p>")
    }

    static func escape(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func tags(matching pattern: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: html) else { return nil }
            return String(html[swiftRange])
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"\b\#(escapedName)\s*=\s*"([^"]*)""#,
            #"\b\#(escapedName)\s*=\s*'([^']*)'"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
            guard
                let match = regex.firstMatch(in: tag, range: range),
                match.numberOfRanges >= 2,
                let valueRange = Range(match.range(at: 1), in: tag)
            else { continue }
            return decodeEntities(String(tag[valueRange]))
        }
        return nil
    }

    private static func decodeEntities(_ raw: String) -> String {
        var result = raw
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private static func fileExtension(for mediaType: String?) -> String {
        switch mediaType?.lowercased() {
        case "image/jpeg", "image/jpg": "jpg"
        case "image/gif": "gif"
        case "image/tiff": "tiff"
        case "image/heic": "heic"
        default: "png"
        }
    }
}
