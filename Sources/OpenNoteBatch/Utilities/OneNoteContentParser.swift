import Foundation

enum OneNoteContentParser {
    static func parse(data: Data, contentType: String?) -> OneNotePageContent {
        let payload = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard
            let contentType,
            contentType.localizedCaseInsensitiveContains("multipart/"),
            let boundary = boundary(from: contentType)
        else {
            return OneNotePageContent(html: payload)
        }

        var html = ""
        var inkML: [String] = []
        let marker = "--\(boundary)"
        for rawPart in payload.components(separatedBy: marker) {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty, part != "--" else { continue }
            let separator: String
            if part.contains("\r\n\r\n") {
                separator = "\r\n\r\n"
            } else {
                separator = "\n\n"
            }
            guard let separatorRange = part.range(of: separator) else { continue }
            let headers = String(part[..<separatorRange.lowerBound])
            var body = String(part[separatorRange.upperBound...])
            if body.hasSuffix("--") {
                body.removeLast(2)
            }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)

            if headers.localizedCaseInsensitiveContains("text/html")
                || headers.localizedCaseInsensitiveContains("application/xhtml+xml")
                || body.range(of: "<html", options: .caseInsensitive) != nil {
                html = body
            }
            if headers.localizedCaseInsensitiveContains("application/inkml+xml")
                || body.range(of: "<inkml:ink", options: .caseInsensitive) != nil
                || body.range(of: "<ink ", options: .caseInsensitive) != nil {
                inkML.append(body)
            }
        }

        return OneNotePageContent(html: html.isEmpty ? payload : html, inkML: inkML)
    }

    private static func boundary(from contentType: String) -> String? {
        let pattern = #"boundary\s*=\s*(?:"([^"]+)"|([^;\s]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(contentType.startIndex..<contentType.endIndex, in: contentType)
        guard let match = regex.firstMatch(in: contentType, range: range) else { return nil }
        for capture in 1..<match.numberOfRanges where match.range(at: capture).location != NSNotFound {
            if let valueRange = Range(match.range(at: capture), in: contentType) {
                return String(contentType[valueRange])
            }
        }
        return nil
    }
}
