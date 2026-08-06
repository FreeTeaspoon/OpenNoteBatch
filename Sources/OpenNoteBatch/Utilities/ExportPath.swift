import Foundation

enum ExportPath {
    static func pageDirectory(for page: PageNode, outputDirectory: URL) -> URL {
        pagePathComponents(for: page).reduce(outputDirectory) { directory, component in
            directory.appendingPathComponent(Filename.safe(component))
        }
    }

    static func pagePathComponents(for page: PageNode) -> [String] {
        var components: [String] = []

        if let notebookName = nonEmpty(page.notebookName) {
            components.append(notebookName)
        }

        if let sectionName = nonEmpty(page.sectionName) {
            components.append(contentsOf: sectionName
                .split(separator: "/")
                .compactMap { nonEmpty(String($0)) })
        }

        components.append(page.title)
        return components
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
