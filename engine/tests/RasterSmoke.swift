import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@main struct RasterSmoke {
    @MainActor static func main() async throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        // Check real pixels, including a nested image and transformed, clipped layer.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="600" height="300" viewBox="0 0 600 300">
        <defs><clipPath id="crop"><rect width="300" height="300"/></clipPath></defs>
        <rect width="600" height="300" fill="blue"/>
        <g transform="translate(300 0)" clip-path="url(#crop)">
        <image width="300" height="300" preserveAspectRatio="none" href="zakka-media:0"/></g></svg>
        """
        let tile = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>
        """
        let png = try await ArtworkRaster.shared.png(svg: svg, images: [
            "data:image/svg+xml;base64," + Data(tile.utf8).base64EncodedString()
        ], width: 120, height: 60)
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
        precondition(image.width == 120 && image.height == 60)
        var pixels = [UInt8](repeating: 0, count: 120 * 60 * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let bitmap = CGContext(data: bytes.baseAddress, width: 120, height: 60, bitsPerComponent: 8,
                                   bytesPerRow: 480, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 120, height: 60))
        }
        precondition(pixels[20 * 4 + 2] > 240 && pixels[80 * 4] > 240, "Embedded image did not render")
        print("WebKit raster: 120×60 canvas, embedded SVG and clip verified")

        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let engine = ArtworkEngine(directory: directory)
        let json = Data("""
        {"version":1,"canvas":{"width":640,"height":320,"backgroundColor":"#0000ff"},"layers":[
          {"kind":"photo","id":"p","assetId":"asset_nasa","x":320,"y":0,"width":320,"height":320,"rotation":0,"locked":false,"opacity":1,"fit":"cover"},
          {"kind":"text","id":"t","text":"Moon **rising**","fontFamily":"Love Ya Like A Sister","align":"left","color":"#000000","fontSize":20,
           "x":10,"y":10,"width":260,"height":80,"rotation":0,"locked":false,"opacity":1}]}
        """.utf8)
        let plan = try await engine.plan(json: json, maps: false, editor: true, thumbnail: false)
        precondition(plan.resources.count == 1 && plan.omitted == 0 && plan.svg.contains("<path"))
        let bitmap = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let jpeg = bytes as Data
        let meta = Data("""
        {"thumbnailUrl":"/api/v1/assets/asset_nasa/variants/small","variants":[
          {"kind":"preview","contentUrl":"/api/v1/assets/asset_nasa/variants/preview"}]}
        """.utf8)
        for thumbnail in [true, false] {
            let uri = try await ArtworkMedia.fetch(plan.resources[0], thumbnail: thumbnail, edge: 320) { path in
                if path == "/assets/asset_nasa" { return meta }
                precondition(path == "/assets/asset_nasa/variants/" + (thumbnail ? "small" : "preview"))
                return jpeg
            }
            let png = try await ArtworkRaster.shared.png(svg: plan.svg, images: [uri], width: 160, height: 80)
            let page = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
            precondition(page.width == 160 && page.height == 80)
            guard let crop = page.cropping(to: CGRect(x: 120, y: 40, width: 1, height: 1)) else { fatalError() }
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes { p in
                let context = CGContext(data: p.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            precondition(pixel[0] > 240 && pixel[1] < 15, "Resolved JPEG missing from editor-core output")
        }
        print("JSC → actual thumbnail/preview URL selection → WebKit: photo pixels verified in both tiers")
    }
}
