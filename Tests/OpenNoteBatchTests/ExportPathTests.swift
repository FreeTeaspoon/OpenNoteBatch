import Foundation
import Testing
@testable import OpenNoteBatch

@Suite("Export paths")
struct ExportPathTests {
    @Test func retainsNotebookNestedSectionsAndPage() {
        let page = PageNode(
            id: "page-1",
            title: "Summer Holiday Homework",
            createdDateTime: nil,
            lastModifiedDateTime: nil,
            contentURL: nil,
            notebookName: "MM (up to 16)",
            sectionName: "Holiday Homework / Term 1"
        )
        let output = URL(fileURLWithPath: "/tmp/OpenNoteBatch-export")

        #expect(ExportPath.pagePathComponents(for: page) == [
            "MM (up to 16)",
            "Holiday Homework",
            "Term 1",
            "Summer Holiday Homework"
        ])
        #expect(ExportPath.pageDirectory(for: page, outputDirectory: output).path ==
            "/tmp/OpenNoteBatch-export/MM (up to 16)/Holiday Homework/Term 1/Summer Holiday Homework")
    }

    @Test func sanitizesEachHierarchyComponentIndependently() {
        let page = PageNode(
            id: "page-2",
            title: "Page/Two",
            createdDateTime: nil,
            lastModifiedDateTime: nil,
            contentURL: nil,
            notebookName: "Notebook/One",
            sectionName: "Group One / Section:Two"
        )
        let output = URL(fileURLWithPath: "/tmp/OpenNoteBatch-export")

        #expect(ExportPath.pageDirectory(for: page, outputDirectory: output).path ==
            "/tmp/OpenNoteBatch-export/Notebook_One/Group One/Section:Two/Page_Two")
    }
}
