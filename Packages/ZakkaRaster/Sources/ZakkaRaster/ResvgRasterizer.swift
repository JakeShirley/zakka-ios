import CResvg
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RasterError: Error { case options, font, svg(Int32), dimensions, png }

/// A font database and resvg context, intended to be owned by one serial render actor.
public final class ResvgRasterizer {
    private let options: OpaquePointer

    public init(fonts: [Data]) throws {
        guard !fonts.isEmpty, fonts.allSatisfy({ !$0.isEmpty }) else { throw RasterError.font }
        guard let options = resvg_options_create() else { throw RasterError.options }
        self.options = options
        for font in fonts {
            font.withUnsafeBytes { bytes in
                resvg_options_load_font_data(options, bytes.bindMemory(to: CChar.self).baseAddress, UInt(bytes.count))
            }
        }
        resvg_options_set_font_family(options, "Lato")
        resvg_options_set_sans_serif_family(options, "Lato")
        resvg_options_set_serif_family(options, "Baskervville")
        resvg_options_set_cursive_family(options, "Baskervville")
        resvg_options_set_fantasy_family(options, "Lato")
        resvg_options_set_monospace_family(options, "Lato")
    }

    deinit { resvg_options_destroy(options) }

    public func png(svg: Data, width: Int, height: Int) throws -> Data {
        guard !svg.isEmpty, (1...2048).contains(width), (1...2048).contains(height) else { throw RasterError.dimensions }
        var parsed: OpaquePointer?
        let status = svg.withUnsafeBytes { bytes in
            resvg_parse_tree_from_data(bytes.bindMemory(to: CChar.self).baseAddress, UInt(bytes.count), options, &parsed)
        }
        guard status == 0, let tree = parsed else { throw RasterError.svg(status) }
        defer { resvg_tree_destroy(tree) }
        let size = resvg_get_image_size(tree)
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { throw RasterError.dimensions }
        var transform = resvg_transform_identity()
        transform.a = Float(width) / size.width
        transform.d = Float(height) / size.height
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            resvg_render(tree, transform, UInt32(width), UInt32(height), bytes.bindMemory(to: CChar.self).baseAddress)
        }
        let info = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let provider = CGDataProvider(data: pixels as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space, bitmapInfo: info, provider: provider,
                                  decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw RasterError.png }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw RasterError.png }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw RasterError.png }
        return output as Data
    }
}
