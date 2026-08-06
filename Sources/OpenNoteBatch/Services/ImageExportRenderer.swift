import AppKit
import Foundation
import ImageIO

enum InkMLParser {
    static func strokes(from documents: [String]) -> [InkStroke] {
        documents.flatMap { document in
            let delegate = InkMLDelegate()
            let parser = XMLParser(data: Data(document.utf8))
            parser.delegate = delegate
            parser.parse()
            return delegate.strokes
        }
    }
}

@MainActor
enum ImageExportRenderer {
    struct RenderedImage {
        var data: Data
        var fileExtension: String
        var includedDrawings: Bool
    }

    static func render(
        imageData: Data,
        resource: AttachmentResource,
        strokes: [InkStroke]
    ) throws -> RenderedImage {
        guard let sourceImage = cgImage(from: imageData) else {
            throw OpenNoteError.fileSystem("The downloaded resource is not a supported image format.")
        }

        guard
            !strokes.isEmpty,
            let pageTop = resource.pageTop,
            let pageLeft = resource.pageLeft
        else {
            return RenderedImage(
                data: imageData,
                fileExtension: resource.resourceFileExtension,
                includedDrawings: false
            )
        }

        let pixelWidth = sourceImage.width
        let pixelHeight = sourceImage.height
        let displayWidth = resource.displayWidth ?? Double(pixelWidth)
        let displayHeight = resource.displayHeight ?? Double(pixelHeight)
        guard displayWidth > 0, displayHeight > 0 else {
            return RenderedImage(
                data: imageData,
                fileExtension: resource.resourceFileExtension,
                includedDrawings: false
            )
        }

        let pageFrame = CGRect(x: pageLeft, y: pageTop, width: displayWidth, height: displayHeight)
        let overlapping = strokes.filter { stroke in
            guard let bounds = stroke.bounds else { return false }
            return bounds.insetBy(dx: -stroke.width, dy: -stroke.width).intersects(pageFrame)
        }
        guard !overlapping.isEmpty else {
            return RenderedImage(
                data: imageData,
                fileExtension: resource.resourceFileExtension,
                includedDrawings: false
            )
        }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OpenNoteError.fileSystem("Could not create an image drawing surface.")
        }

        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let scaleX = Double(pixelWidth) / displayWidth
        let scaleY = Double(pixelHeight) / displayHeight
        for stroke in overlapping where !stroke.points.isEmpty {
            let color = NSColor(hex: stroke.colorHex, opacity: stroke.opacity)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(max(0.5, stroke.width * ((scaleX + scaleY) / 2)))
            context.beginPath()
            for (index, point) in stroke.points.enumerated() {
                let local = CGPoint(
                    x: (point.x - pageLeft) * scaleX,
                    y: Double(pixelHeight) - ((point.y - pageTop) * scaleY)
                )
                if index == 0 {
                    context.move(to: local)
                } else {
                    context.addLine(to: local)
                }
            }
            context.strokePath()
        }

        guard
            let outputImage = context.makeImage(),
            let png = NSBitmapImageRep(cgImage: outputImage).representation(using: .png, properties: [:])
        else {
            throw OpenNoteError.fileSystem("Could not encode the annotated image.")
        }
        return RenderedImage(data: png, fileExtension: "png", includedDrawings: true)
    }

    static func isSupportedImageData(_ data: Data) -> Bool {
        cgImage(from: data) != nil
    }

    static func writePDF(images: [Data], to url: URL) throws {
        guard !images.isEmpty else {
            throw OpenNoteError.fileSystem("Could not create a PDF without any images.")
        }

        let sourceImages = try images.enumerated().map { index, data in
            guard let image = cgImage(from: data) else {
                throw OpenNoteError.fileSystem("Could not decode image \(index + 1) for the PDF.")
            }
            return image
        }

        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else {
            throw OpenNoteError.fileSystem("Could not write \(url.lastPathComponent).")
        }
        for image in sourceImages {
            var mediaBox = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
            context.beginPage(mediaBox: &mediaBox)
            context.interpolationQuality = CGInterpolationQuality.high
            context.draw(image, in: mediaBox)
            context.endPage()
        }
        context.closePDF()
    }

    private static func cgImage(from data: Data) -> CGImage? {
        if
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        {
            return image
        }

        guard let image = NSImage(data: data) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

private final class InkMLDelegate: NSObject, XMLParserDelegate {
    struct Brush {
        var widthHimetric = 100.0
        var colorHex = "#000000"
        var transparency = 0.0
    }

    var strokes: [InkStroke] = []
    private var brushes: [String: Brush] = [:]
    private var currentBrushID: String?
    private var currentTraceBrushID: String?
    private var traceText = ""
    private var isParsingTrace = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(qName ?? elementName) {
        case "brush":
            currentBrushID = identifier(in: attributeDict)
            if let currentBrushID {
                brushes[currentBrushID] = Brush()
            }
        case "brushProperty":
            guard let currentBrushID else { return }
            var brush = brushes[currentBrushID] ?? Brush()
            switch attributeDict["name"]?.lowercased() {
            case "width":
                brush.widthHimetric = Double(attributeDict["value"] ?? "") ?? brush.widthHimetric
            case "color":
                brush.colorHex = attributeDict["value"] ?? brush.colorHex
            case "transparency":
                brush.transparency = Double(attributeDict["value"] ?? "") ?? brush.transparency
            default:
                break
            }
            brushes[currentBrushID] = brush
        case "trace":
            currentTraceBrushID = attributeDict["brushRef"]?.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            traceText = ""
            isParsingTrace = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isParsingTrace {
            traceText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localName(qName ?? elementName) {
        case "brush":
            currentBrushID = nil
        case "trace":
            let brush = currentTraceBrushID.flatMap { brushes[$0] } ?? Brush()
            let points = traceText
                .split(separator: ",")
                .compactMap { sample -> CGPoint? in
                    let values = sample.split(whereSeparator: \.isWhitespace)
                    guard
                        values.count >= 2,
                        let x = Double(values[0]),
                        let y = Double(values[1])
                    else { return nil }
                    return CGPoint(x: x.himetricPixels, y: y.himetricPixels)
                }
            if !points.isEmpty {
                strokes.append(InkStroke(
                    points: points,
                    colorHex: brush.colorHex,
                    width: max(0.5, brush.widthHimetric.himetricPixels),
                    opacity: max(0, min(1, 1 - (brush.transparency / 255)))
                ))
            }
            currentTraceBrushID = nil
            traceText = ""
            isParsingTrace = false
        default:
            break
        }
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    private func identifier(in attributes: [String: String]) -> String? {
        attributes["xml:id"] ?? attributes["id"]
    }
}

private extension Double {
    var himetricPixels: Double {
        self * 96 / 2_540
    }
}

private extension InkStroke {
    var bounds: CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private extension AttachmentResource {
    var resourceFileExtension: String {
        switch mediaType?.lowercased() {
        case "image/jpeg", "image/jpg": "jpg"
        case "image/gif": "gif"
        case "image/tiff": "tiff"
        case "image/heic": "heic"
        default: URL(fileURLWithPath: fileName).pathExtension.isEmpty
            ? "png"
            : URL(fileURLWithPath: fileName).pathExtension
        }
    }
}

private extension NSColor {
    convenience init(hex: String, opacity: Double) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let parsed = UInt64(value, radix: 16) ?? 0
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if value.count == 3 {
            red = CGFloat((parsed >> 8) & 0xF) / 15
            green = CGFloat((parsed >> 4) & 0xF) / 15
            blue = CGFloat(parsed & 0xF) / 15
        } else {
            red = CGFloat((parsed >> 16) & 0xFF) / 255
            green = CGFloat((parsed >> 8) & 0xFF) / 255
            blue = CGFloat(parsed & 0xFF) / 255
        }
        self.init(srgbRed: red, green: green, blue: blue, alpha: opacity)
    }
}
