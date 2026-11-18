import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct RasterSmoke {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let raster = ArtworkRaster(directory: directory)
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
        let png = try await raster.png(svg: svg, images: [
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
        print("resvg C API: 120×60 canvas, embedded SVG and clip verified")

        let engine = ArtworkEngine(directory: directory)
        let json = Data("""
        {"version":1,"canvas":{"width":640,"height":320,"backgroundColor":"#0000ff"},"layers":[
          {"kind":"photo","id":"p","assetId":"asset_nasa","x":320,"y":0,"width":320,"height":320,"rotation":0,"locked":false,"opacity":1,"fit":"cover"},
          {"kind":"text","id":"t","text":"Moon **rising**","fontFamily":"Love Ya Like A Sister","align":"left","color":"#ffffff","fontSize":32,
           "x":10,"y":10,"width":280,"height":80,"rotation":0,"locked":false,"opacity":1},
          {"kind":"text","id":"r","text":"Native type","fontFamily":"Inter, sans-serif","align":"left","color":"#00ff00","fontSize":50,
           "x":10,"y":100,"width":300,"height":90,"rotation":0,"locked":false,"opacity":1}]}
        """.utf8)
        let plan = try await engine.plan(json: json, maps: false, editor: true, thumbnail: false)
        precondition(plan.resources.count == 1 && plan.omitted == 0 && plan.svg.contains("<path") && plan.svg.contains("<text "))
        let jpeg = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let expected = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(jpeg as CFData, nil)!, 0, nil)!
        var photo = [UInt8](repeating: 0, count: 80 * 80 * 4)
        photo.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 320,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(expected, in: CGRect(x: 0, y: 0, width: 80, height: 80))
        }
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
            let png = try await raster.png(svg: plan.svg, images: [uri], width: 160, height: 80)
            let page = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
            precondition(page.width == 160 && page.height == 80)
            var white = 0, green = 0
            var pagePixels = [UInt8](repeating: 0, count: 160 * 80 * 4)
            pagePixels.withUnsafeMutableBytes { p in
                let context = CGContext(data: p.baseAddress, width: 160, height: 80, bitsPerComponent: 8, bytesPerRow: 640,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(page, in: CGRect(x: 0, y: 0, width: 160, height: 80))
            }
            var delta = 0
            for y in 0..<80 {
                for x in 0..<80 {
                    let i = (160 * y + x) * 4
                    if pagePixels[i] > 130 && pagePixels[i+1] > 130 && pagePixels[i+2] > 130 { white += 1 }
                    if pagePixels[i+1] > 130 && pagePixels[i] < 30 && pagePixels[i+2] < 130 { green += 1 }
                    for c in 0..<3 {
                        delta += abs(Int(pagePixels[i + 80*4 + c]) - Int(photo[(80*y + x)*4 + c]))
                    }
                }
            }
            let mae = Double(delta) / (80 * 80 * 3)
            precondition(mae < 15, "Rendered photo differs from reference: mean RGB error \(mae)")
            precondition(white > 12 && green > 12, "Editor-core glyph outlines or fontdb SVG text failed to paint: \(white), \(green)")
            if !thumbnail {
                try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
                print("NASA photo mean RGB error \(mae)/255; \(white) outlined and \(green) fontdb text pixels")
            }
        }
        print("JSC → thumbnail/preview URL selection → resvg: real JPEG and both text paths verified in both tiers")
    }
}
