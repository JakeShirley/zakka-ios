import Foundation
import ZakkaRaster

actor ArtworkRaster {
    static let shared = ArtworkRaster()
    private let directory: URL?
    private var renderer: ResvgRasterizer?
    private let references = try! NSRegularExpression(pattern: #" href="zakka-media:(\d+)""#)
    init(directory: URL? = Bundle.main.url(forResource: "ZakkaArtwork", withExtension: "bundle")) {
        self.directory = directory
    }

    func png(svg: String, images: [String], width: Int, height: Int) throws -> Data {
        try Task.checkCancellation()
        if renderer == nil {
            guard let directory else { throw ArtworkError.missingBundle }
            let fonts = try ["lato-400", "baskervville-400"].map {
                try Data(contentsOf: directory.appendingPathComponent("\($0).ttf"))
            }
            renderer = try ResvgRasterizer(fonts: fonts)
        }
        let markup = svg as NSString
        let matches = references.matches(in: svg, range: NSRange(location: 0, length: markup.length))
        var source = Data()
        var cursor = 0
        for match in matches {
            source.append(contentsOf: markup.substring(with: NSRange(location: cursor, length: match.range.location - cursor)).utf8)
            if let index = Int(markup.substring(with: match.range(at: 1))),
               images.indices.contains(index), !images[index].isEmpty {
                source.append(contentsOf: " href=\"".utf8)
                guard source.count + images[index].utf8.count <= 48 * 1024 * 1024 else { throw ArtworkError.tooLarge }
                source.append(contentsOf: images[index].utf8)
                source.append(34)
            }
            cursor = NSMaxRange(match.range)
        }
        source.append(contentsOf: markup.substring(from: cursor).utf8)
        guard source.count <= 48 * 1024 * 1024 else { throw ArtworkError.tooLarge }
        try Task.checkCancellation()
        guard let renderer else { throw ArtworkError.missingBundle }
        return try renderer.png(svg: source, width: width, height: height)
    }
}
