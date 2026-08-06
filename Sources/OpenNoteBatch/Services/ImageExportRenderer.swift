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

    /// Renders the page coordinate space instead of cropping ink to one image.
    ///
    /// Individual image exports remain image-sized, while this renderer is used
    /// for the additional page-level annotated output. The tuple order must be
    /// the visual order returned by `OneNoteHTML.images(from:page:)`.
    static func renderPage(
        images: [(resource: AttachmentResource, data: Data)],
        strokes: [InkStroke]
    ) throws -> RenderedImage? {
        guard !images.isEmpty, !strokes.isEmpty else { return nil }

        struct DecodedImage {
            var image: CGImage
            var frame: CGRect
        }

        var decodedImages: [DecodedImage] = []
        for item in images {
            guard let image = cgImage(from: item.data) else {
                throw OpenNoteError.fileSystem("The downloaded resource is not a supported image format.")
            }

            guard
                let pageTop = item.resource.pageTop,
                let pageLeft = item.resource.pageLeft
            else {
                // A page composite cannot preserve placement without the
                // resource's absolute position. The caller can retain the
                // individual image exports and report this as a warning.
                return nil
            }

            let displayWidth = item.resource.displayWidth ?? Double(image.width)
            let displayHeight = item.resource.displayHeight ?? Double(image.height)
            guard
                displayWidth.isFinite,
                displayHeight.isFinite,
                displayWidth > 0,
                displayHeight > 0
            else {
                return nil
            }

            decodedImages.append(DecodedImage(
                image: image,
                frame: CGRect(
                    x: CGFloat(pageLeft),
                    y: CGFloat(pageTop),
                    width: CGFloat(displayWidth),
                    height: CGFloat(displayHeight)
                )
            ))
        }

        let renderableStrokes = strokes.filter { stroke in
            guard let bounds = stroke.bounds else { return false }
            return bounds.minX.isFinite
                && bounds.minY.isFinite
                && bounds.maxX.isFinite
                && bounds.maxY.isFinite
                && !stroke.points.isEmpty
        }
        guard !renderableStrokes.isEmpty else { return nil }

        var contentBounds = decodedImages.reduce(CGRect.null) { result, decoded in
            result.union(decoded.frame)
        }
        for stroke in renderableStrokes {
            guard let bounds = stroke.bounds else { continue }
            contentBounds = contentBounds.union(
                bounds.insetBy(dx: CGFloat(stroke.width / 2), dy: CGFloat(stroke.width / 2))
            )
        }
        guard
            !contentBounds.isNull,
            contentBounds.width.isFinite,
            contentBounds.height.isFinite,
            contentBounds.width > 0,
            contentBounds.height > 0
        else {
            return nil
        }

        // Keep a small amount of page context around the outermost image or
        // stroke so handwriting at an edge is not clipped by the export.
        let pageBounds = contentBounds.insetBy(dx: -24, dy: -24)
        let sourceScale = decodedImages.map { decoded in
            max(
                Double(decoded.image.width) / Double(decoded.frame.width),
                Double(decoded.image.height) / Double(decoded.frame.height)
            )
        }.max() ?? 1
        let scale = boundedPageScale(
            sourceScale,
            width: Double(pageBounds.width),
            height: Double(pageBounds.height)
        )
        let pixelWidth = max(1, Int((Double(pageBounds.width) * scale).rounded(.up)))
        let pixelHeight = max(1, Int((Double(pageBounds.height) * scale).rounded(.up)))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OpenNoteError.fileSystem("Could not create a page drawing surface.")
        }

        let canvas = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(canvas)
        context.interpolationQuality = .high

        for decoded in decodedImages {
            let destination = CGRect(
                x: CGFloat((Double(decoded.frame.minX) - Double(pageBounds.minX)) * scale),
                y: CGFloat((Double(pageBounds.maxY) - Double(decoded.frame.maxY)) * scale),
                width: CGFloat(Double(decoded.frame.width) * scale),
                height: CGFloat(Double(decoded.frame.height) * scale)
            )
            context.draw(decoded.image, in: destination)
        }

        drawStrokes(
            renderableStrokes,
            in: context,
            lineScale: scale
        ) { point in
            CGPoint(
                x: CGFloat((Double(point.x) - Double(pageBounds.minX)) * scale),
                y: CGFloat(Double(pixelHeight) - ((Double(point.y) - Double(pageBounds.minY)) * scale))
            )
        }

        guard
            let outputImage = context.makeImage(),
            let png = NSBitmapImageRep(cgImage: outputImage).representation(using: .png, properties: [:])
        else {
            throw OpenNoteError.fileSystem("Could not encode the full-page annotated image.")
        }
        return RenderedImage(data: png, fileExtension: "png", includedDrawings: true)
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

        let pageFrame = CGRect(
            x: CGFloat(pageLeft),
            y: CGFloat(pageTop),
            width: CGFloat(displayWidth),
            height: CGFloat(displayHeight)
        )
        let overlapping = strokes.filter { stroke in
            guard let bounds = stroke.bounds else { return false }
            return bounds
                .insetBy(dx: -CGFloat(stroke.width), dy: -CGFloat(stroke.width))
                .intersects(pageFrame)
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
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        )

        let scaleX = Double(pixelWidth) / displayWidth
        let scaleY = Double(pixelHeight) / displayHeight
        drawStrokes(
            overlapping,
            in: context,
            lineScale: (scaleX + scaleY) / 2
        ) { point in
            CGPoint(
                x: CGFloat((Double(point.x) - pageLeft) * scaleX),
                y: CGFloat(Double(pixelHeight) - ((Double(point.y) - pageTop) * scaleY))
            )
        }

        guard
            let outputImage = context.makeImage(),
            let png = NSBitmapImageRep(cgImage: outputImage).representation(using: .png, properties: [:])
        else {
            throw OpenNoteError.fileSystem("Could not encode the annotated image.")
        }
        return RenderedImage(data: png, fileExtension: "png", includedDrawings: true)
    }

    private static func drawStrokes(
        _ strokes: [InkStroke],
        in context: CGContext,
        lineScale: Double,
        mapPoint: (CGPoint) -> CGPoint
    ) {
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes where !stroke.points.isEmpty {
            let color = NSColor(hex: stroke.colorHex, opacity: stroke.opacity)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(CGFloat(max(0.5, stroke.width * lineScale)))
            context.beginPath()
            for (index, point) in stroke.points.enumerated() {
                let local = mapPoint(point)
                if index == 0 {
                    context.move(to: local)
                } else {
                    context.addLine(to: local)
                }
            }
            context.strokePath()
        }
    }

    private static func boundedPageScale(
        _ requestedScale: Double,
        width: Double,
        height: Double
    ) -> Double {
        let scale = max(0.01, requestedScale.isFinite ? requestedScale : 1)
        let maxDimension = 16_384.0
        let maxPixels = 50_000_000.0
        let dimensionScale = min(
            maxDimension / max(width, 1),
            maxDimension / max(height, 1)
        )
        let pixelScale = sqrt(maxPixels / max(width * height, 1))
        return min(scale, dimensionScale, pixelScale)
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

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let context = CGContext(temporaryURL as CFURL, mediaBox: nil, nil) else {
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

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
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
