import AppKit
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

    @Test func ordersImagesByVisualPosition() {
        let page = PageNode(id: "p1", title: "Page", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil)
        let html = """
        <html><body data-absolute-enabled="true">
          <div style="position:absolute;left:300px;top:600px">
            <img width="100" height="50"
                 src="https://graph.microsoft.com/v1.0/me/onenote/resources/lower/content"
                 data-src-type="image/jpeg" />
          </div>
          <img style="position:absolute;left:100px;top:200px" width="200" height="100"
               src="https://graph.microsoft.com/v1.0/me/onenote/resources/upper/content"
               data-src-type="image/png" />
        </body></html>
        """

        let images = OneNoteHTML.images(from: html, page: page)

        #expect(images.count == 2)
        #expect(images[0].resourceURL.absoluteString.contains("upper"))
        #expect(images[0].fileName == "image-001.png")
        #expect(images[0].pageTop == 200)
        #expect(images[0].pageLeft == 100)
        #expect(images[1].resourceURL.absoluteString.contains("lower"))
        #expect(images[1].fileName == "image-002.jpg")
        #expect(images[1].pageTop == 600)
        #expect(images[1].pageLeft == 300)
    }

    @Test func keepsWebReadyImageAsFullResolutionFallback() {
        let page = PageNode(id: "p1", title: "Page", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil)
        let html = """
        <img src="https://graph.microsoft.com/v1.0/me/onenote/resources/web/content"
             data-fullres-src="https://graph.microsoft.com/v1.0/me/onenote/resources/full/content"
             data-src-type="image/png"
             data-fullres-src-type="image/png" />
        """

        let image = OneNoteHTML.images(from: html, page: page).first

        #expect(image?.resourceURL.absoluteString.contains("/full/") == true)
        #expect(image?.alternateResourceURL?.absoluteString.contains("/web/") == true)
    }

    @Test func convertsPlainText() {
        let html = "<html><body><p>Hello&nbsp;world</p><p>Second &amp; third</p></body></html>"

        #expect(OneNoteHTML.plainText(from: html) == "Hello world\nSecond & third")
    }
}

@Suite("OneNote multipart content")
struct OneNoteContentParserTests {
    @Test func separatesHTMLAndInkML() {
        let boundary = "sample-boundary"
        let payload = """
        --\(boundary)\r
        Content-Type: text/html\r
        \r
        <html><body><p>Page</p></body></html>\r
        --\(boundary)\r
        Content-Type: application/inkml+xml\r
        \r
        <inkml:ink xmlns:inkml="http://www.w3.org/2003/InkML"></inkml:ink>\r
        --\(boundary)--\r
        """

        let content = OneNoteContentParser.parse(
            data: Data(payload.utf8),
            contentType: "multipart/mixed; boundary=\"\(boundary)\""
        )

        #expect(content.html.contains("<p>Page</p>"))
        #expect(content.inkML.count == 1)
        #expect(content.inkML[0].contains("<inkml:ink"))
    }

    @Test func parsesInkCoordinatesAndBrush() {
        let inkML = """
        <?xml version="1.0" encoding="utf-8"?>
        <inkml:ink xmlns:inkml="http://www.w3.org/2003/InkML">
          <inkml:definitions>
            <inkml:brush xml:id="br0">
              <inkml:brushProperty name="width" value="100" units="himetric"/>
              <inkml:brushProperty name="color" value="#FF0000"/>
              <inkml:brushProperty name="transparency" value="0"/>
            </inkml:brush>
          </inkml:definitions>
          <inkml:trace brushRef="#br0">2540 5080 100, 5080 7620 200</inkml:trace>
        </inkml:ink>
        """

        let strokes = InkMLParser.strokes(from: [inkML])

        #expect(strokes.count == 1)
        #expect(strokes[0].colorHex == "#FF0000")
        #expect(abs(strokes[0].width - 3.7795) < 0.001)
        #expect(strokes[0].points == [CGPoint(x: 96, y: 192), CGPoint(x: 192, y: 288)])
    }

    @Test @MainActor func rendersDrawingAndCreatesPDF() throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 20,
            pixelsHigh: 20,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        let imageData = bitmap.representation(using: .png, properties: [:])!
        let resource = AttachmentResource(
            fileName: "image-001.png",
            resourceURL: URL(string: "https://graph.microsoft.com/v1.0/me/onenote/resources/r1/content")!,
            mediaType: "image/png",
            pageTitle: "Page",
            pageID: "p1",
            kind: "image",
            pageTop: 0,
            pageLeft: 0,
            displayWidth: 20,
            displayHeight: 20
        )
        let stroke = InkStroke(
            points: [CGPoint(x: 2, y: 2), CGPoint(x: 18, y: 18)],
            colorHex: "#FF0000",
            width: 2,
            opacity: 1
        )

        let rendered = try ImageExportRenderer.render(
            imageData: imageData,
            resource: resource,
            strokes: [stroke]
        )

        #expect(rendered.includedDrawings)
        #expect(rendered.fileExtension == "png")
        #expect(NSImage(data: rendered.data) != nil)

        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenNoteBatch-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        try ImageExportRenderer.writePDF(images: [rendered.data], to: pdfURL)
        try ImageExportRenderer.writePDF(images: [rendered.data], to: pdfURL)
        #expect((try Data(contentsOf: pdfURL)).starts(with: Data("%PDF".utf8)))
    }

    @Test @MainActor func rendersPageAnnotationOutsideEmbeddedImage() throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 20,
            pixelsHigh: 20,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        let imageData = bitmap.representation(using: .png, properties: [:])!
        let resource = AttachmentResource(
            fileName: "image-001.png",
            resourceURL: URL(string: "https://graph.microsoft.com/v1.0/me/onenote/resources/r1/content")!,
            mediaType: "image/png",
            pageTitle: "Page",
            pageID: "p1",
            kind: "image",
            pageTop: 20,
            pageLeft: 20,
            displayWidth: 20,
            displayHeight: 20
        )
        let outsideStroke = InkStroke(
            points: [CGPoint(x: 50, y: 25), CGPoint(x: 60, y: 25)],
            colorHex: "#FF0000",
            width: 2,
            opacity: 1
        )

        let rendered = try ImageExportRenderer.renderPage(
            images: [(resource: resource, data: imageData)],
            strokes: [outsideStroke]
        )

        guard let rendered else {
            Issue.record("Expected a full-page composite when ink is outside the image frame.")
            return
        }
        let output = try #require(NSBitmapImageRep(data: rendered.data))
        #expect(rendered.includedDrawings)
        #expect(output.pixelsWide > 20)
        #expect(output.pixelsHigh > 20)
    }

    @Test @MainActor func detectsUnsupportedFullResolutionImageData() throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let fallback = bitmap.representation(using: .png, properties: [:])!
        let metafileHeader = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        #expect(!ImageExportRenderer.isSupportedImageData(metafileHeader))
        #expect(ImageExportRenderer.isSupportedImageData(fallback))
    }
}

@Suite("OneNote ordering")
struct OneNoteOrderingTests {
    @Test func ordersPagesByOneNoteOrderAndKeepsStableFallbacks() {
        let pages = [
            PageNode(id: "modified-first", title: "Third", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil, order: 30),
            PageNode(id: "unordered-a", title: "Unordered A", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil),
            PageNode(id: "first", title: "First", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil, order: 10),
            PageNode(id: "unordered-b", title: "Unordered B", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil),
            PageNode(id: "second", title: "Second", createdDateTime: nil, lastModifiedDateTime: nil, contentURL: nil, order: 20)
        ]

        #expect(OneNoteOrdering.pages(pages).map(\.id) == [
            "first", "second", "modified-first", "unordered-a", "unordered-b"
        ])
    }
}
