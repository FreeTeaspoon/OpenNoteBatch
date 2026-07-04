import Foundation
import Testing
@testable import OpenNoteBatch

@Suite("OneNote HTML")
struct OneNoteHTMLTests {
    @Test func extractsAttachments() throws {
        let page = PageNode(id: "p1", title: "Page", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil)
        let html = """
        <object data="https://graph.microsoft.com/v1.0/me/onenote/resources/r1/content"
                data-attachment="Test File.docx"
                type="application/vnd.openxmlformats-officedocument.wordprocessingml.document"></object>
        """

        let attachments = OneNoteHTML.attachments(from: html, page: page)

        #expect(attachments.count == 1)
        #expect(attachments[0].fileName == "Test File.docx")
        #expect(attachments[0].kind == "attachment")
    }

    @Test func extractsTags() throws {
        let page = PageNode(id: "p1", title: "Page", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil)
        let html = #"<p data-tag="to-do">Call me</p>"#

        let tags = OneNoteHTML.tags(from: html, page: page)

        #expect(tags.count == 1)
        #expect(tags[0].name == "to-do")
    }

    @Test func convertsPlainText() {
        let html = "<html><body><p>Hello&nbsp;world</p><p>Second &amp; third</p></body></html>"

        #expect(OneNoteHTML.plainText(from: html) == "Hello world\nSecond & third")
    }
}

