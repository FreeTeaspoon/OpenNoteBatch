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
        var stack: [(name: String, top: Double?, left: Double?)] = []
        var images: [AttachmentResource] = []
        var sourceIndex = 0
        let pattern = #"<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>"#

        for token in tags(matching: pattern, in: html) {
            guard let tagName = elementName(in: token)?.lowercased() else { continue }
            let isClosing = token.range(of: #"<\s*/"#, options: .regularExpression) != nil
            let isSelfClosing = token.range(of: #"/\s*>"#, options: .regularExpression) != nil

            if isClosing {
                if let index = stack.lastIndex(where: { $0.name == tagName }) {
                    stack.removeSubrange(index...)
                }
                continue
            }

            let parent = stack.last
            let style = attribute("style", in: token)
            let top = cssPixelValue("top", in: style) ?? parent?.top
            let left = cssPixelValue("left", in: style) ?? parent?.left

            if tagName == "img" {
                let rawFullResolutionURL = attribute("data-fullres-src", in: token)
                let rawWebReadyURL = attribute("src", in: token)
                let rawURL = rawFullResolutionURL ?? rawWebReadyURL
                guard
                    let rawURL,
                    rawURL.contains("/onenote/resources/"),
                    let url = URL(string: rawURL)
                else { continue }

                sourceIndex += 1
                let mediaType = attribute("data-fullres-src-type", in: token) ?? attribute("data-src-type", in: token)
                let ext = fileExtension(for: mediaType)
                let width = numericAttribute("width", in: token) ?? cssPixelValue("width", in: style)
                let height = numericAttribute("height", in: token) ?? cssPixelValue("height", in: style)
                images.append(AttachmentResource(
                    fileName: "image-\(String(format: "%03d", sourceIndex)).\(ext)",
                    resourceURL: url,
                    alternateResourceURL: rawWebReadyURL
                        .flatMap { $0.contains("/onenote/resources/") ? $0 : nil }
                        .flatMap(URL.init(string:))
                        .flatMap { $0 == url ? nil : $0 },
                    mediaType: mediaType,
                    pageTitle: page.title,
                    pageID: page.id,
                    kind: "image",
                    pageTop: top,
                    pageLeft: left,
                    displayWidth: width,
                    displayHeight: height,
                    documentIndex: sourceIndex
                ))
            } else if !isSelfClosing {
                stack.append((tagName, top, left))
            }
        }

        let sorted = images.sorted { lhs, rhs in
            let lhsTop = lhs.pageTop ?? Double.greatestFiniteMagnitude
            let rhsTop = rhs.pageTop ?? Double.greatestFiniteMagnitude
            if lhsTop != rhsTop { return lhsTop < rhsTop }
            let lhsLeft = lhs.pageLeft ?? Double.greatestFiniteMagnitude
            let rhsLeft = rhs.pageLeft ?? Double.greatestFiniteMagnitude
            if lhsLeft != rhsLeft { return lhsLeft < rhsLeft }
            return lhs.documentIndex < rhs.documentIndex
        }

        return sorted.enumerated().map { index, resource in
            var resource = resource
            resource.fileName = "image-\(String(format: "%03d", index + 1)).\(fileExtension(for: resource.mediaType))"
            return resource
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

    private static func elementName(in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<\s*/?\s*([a-zA-Z][a-zA-Z0-9]*)"#) else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard
            let match = regex.firstMatch(in: tag, range: range),
            let valueRange = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[valueRange])
    }

    private static func cssPixelValue(_ property: String, in style: String?) -> Double? {
        guard let style else { return nil }
        let escapedProperty = NSRegularExpression.escapedPattern(for: property)
        let pattern = #"(?:^|;)\s*\#(escapedProperty)\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)\s*px\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(style.startIndex..<style.endIndex, in: style)
        guard
            let match = regex.firstMatch(in: style, range: range),
            let valueRange = Range(match.range(at: 1), in: style)
        else { return nil }
        return Double(style[valueRange])
    }

    private static func numericAttribute(_ name: String, in tag: String) -> Double? {
        guard let value = attribute(name, in: tag) else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
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
