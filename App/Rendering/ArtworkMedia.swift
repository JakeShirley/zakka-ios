import Foundation
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum ArtworkMedia {
    private struct Asset: Decodable {
        struct Variant: Decodable { let kind: String; let contentUrl: String }
        let thumbnailUrl: String?
        let variants: [Variant]
    }

    /// Keep auth and redirects in ZakkaClient. Only follow variants belonging to the requested asset.
    static func fetch(_ resource: ArtworkPlan.Resource, thumbnail: Bool, edge: Int,
                      read: @Sendable (String) async throws -> Data) async throws -> String {
        // resvg has no Apple Color Emoji bitmap font loader. Preserve the existing
        // system-glyph fallback without copying a system font into the app.
        if let glyph = resource.glyph { return try emoji(glyph, edge: min(edge, 240)) }
        if let path = resource.path {
            let data = try await read(path)
            try Task.checkCancellation()
            return try dataURI(data, edge: edge, allowSVG: path.hasPrefix("/custom-stickers/"))
        }
        guard let id = resource.asset else { throw ArtworkError.imageUnavailable }
        let root = "/assets/\(id)"
        var paths: [String] = []
        if let bytes = try? await read(root),
           let meta = try? JSONDecoder().decode(Asset.self, from: bytes) {
            let preview = meta.variants.first(where: { $0.kind == "preview" })?.contentUrl
            let thumb = meta.thumbnailUrl ?? meta.variants.first(where: { $0.kind == "thumbnail" })?.contentUrl
            func variantPath(_ path: String?) -> String? {
                guard var path else { return nil }
                if path.hasPrefix("/api/v1/") { path = String(path.dropFirst(7)) }
                let prefix = root + "/variants/"
                guard path.hasPrefix(prefix) else { return nil }
                let variant = path.dropFirst(prefix.count)
                guard !variant.isEmpty, variant.utf8.allSatisfy({
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
                }) else { return nil }
                return path
            }
            paths = (thumbnail ? [variantPath(thumb), variantPath(preview), root + "/content"]
                     : [variantPath(preview), root + "/content", variantPath(thumb)]).compactMap { $0 }
        }
        // Legacy imports may not yet have variants. ImageIO can downsample and orient the original.
        if paths.isEmpty { paths.append(root + "/content") }
        for path in paths {
            try Task.checkCancellation()
            if let data = try? await read(path) {
                try Task.checkCancellation()
                if let uri = try? dataURI(data, edge: edge, allowSVG: false) { return uri }
            }
        }
        throw ArtworkError.imageUnavailable
    }

    private static func emoji(_ glyph: String, edge: Int) throws -> String {
        guard let ctx = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: edge * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ArtworkError.imageUnavailable }
        let size = CGFloat(edge)
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, size * 0.8, nil)
        let text = NSAttributedString(string: glyph, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetImageBounds(line, ctx)
        guard !bounds.isEmpty else { throw ArtworkError.imageUnavailable }
        ctx.textPosition = CGPoint(x: size / 2 - bounds.midX, y: size / 2 - bounds.midY)
        CTLineDraw(line, ctx)
        let bytes = NSMutableData()
        guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
        else { throw ArtworkError.imageUnavailable }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ArtworkError.imageUnavailable }
        return "data:image/png;base64," + (bytes as Data).base64EncodedString()
    }

    static func dataURI(_ data: Data, edge: Int, allowSVG: Bool) throws -> String {
        guard data.count <= 24 * 1024 * 1024 else { throw ArtworkError.tooLarge }
        if allowSVG, data.count <= 2 * 1024 * 1024,
           String(decoding: data.prefix(2048), as: UTF8.self).range(of: "<svg", options: .caseInsensitive) != nil {
            // Passed as a nested SVG image, never injected as markup.
            return "data:image/svg+xml;base64," + data.base64EncodedString()
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let type = CGImageSourceGetType(src) as String?, type != UTType.svg.identifier else {
            throw ArtworkError.imageUnavailable
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation == 1, w > 0, h > 0, max(w, h) <= edge, data.count < 768 * 1024,
           let mime = [UTType.jpeg.identifier: "image/jpeg", UTType.png.identifier: "image/png",
                       UTType.webP.identifier: "image/webp"][type] {
            return "data:\(mime);base64," + data.base64EncodedString()
        }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: edge,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ArtworkError.imageUnavailable
        }
        let alpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, (alpha ? UTType.png : .jpeg).identifier as CFString, 1, nil) else {
            throw ArtworkError.imageUnavailable
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ArtworkError.imageUnavailable }
        return "data:image/\(alpha ? "png" : "jpeg");base64," + (output as Data).base64EncodedString()
    }
}
