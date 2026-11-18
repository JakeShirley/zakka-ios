import CryptoKit
import Foundation
import ZakkaCore

struct ArtworkResult: Sendable { let png: Data; let missing: Int }

actor ArtworkPipeline {
    static let shared = ArtworkPipeline()
    private final class Cache {
        let pages = NSCache<NSString, NSData>()
        let media = NSCache<NSString, NSString>()
        init() {
            pages.totalCostLimit = 24 * 1024 * 1024
            media.totalCostLimit = 24 * 1024 * 1024
        }
    }
    private let caches = NSMapTable<ZakkaClient, Cache>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func render(document: JSONValue, client: ZakkaClient, width: Int, height: Int,
                editor: Bool, thumbnail: Bool) async throws -> ArtworkResult {
        if running < 2 { running += 1 }
        else { await withCheckedContinuation { waiting.append($0) } }
        defer {
            if waiting.isEmpty { running -= 1 }
            else { waiting.removeFirst().resume() }
        }
        try Task.checkCancellation()
        let cache = caches.object(forKey: client) ?? Cache()
        caches.setObject(cache, forKey: client)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(document)
        let digest = Data(SHA256.hash(data: json)).base64EncodedString()
        let key = "\(digest):\(width)x\(height):\(editor):\(thumbnail)" as NSString
        if let png = cache.pages.object(forKey: key) { return ArtworkResult(png: png as Data, missing: 0) }
        let maps = document["layers"].items.contains { $0["kind"].text == "map" }
        let plan = try await ArtworkEngine.shared.plan(json: json, maps: maps, editor: editor, thumbnail: thumbnail)
        let count = plan.resources.count
        let mediaEdge = min(max(width, height), max(256, Int(4096 / sqrt(Double(max(1, count))))))
        // Quantize downsample sizes so nearby editor sizes can share cached media.
        let edge = min(2048, max(256, ((mediaEdge + 127) / 128) * 128))
        var images = [String](repeating: "", count: count)
        var missing = plan.omitted, bytes = 0
        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            func submit() {
                let i = next, resource = plan.resources[next]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    let uri = try? await self.load(resource, client: client, thumbnail: thumbnail, edge: edge)
                    try Task.checkCancellation()
                    return (i, uri)
                }
            }
            for _ in 0..<min(3, count) { submit() }
            while let (i, uri) = try await group.next() {
                if let uri {
                    bytes += uri.utf8.count
                    guard bytes <= 32 * 1024 * 1024 else { throw ArtworkError.tooLarge }
                    images[i] = uri
                } else { missing += 1 }
                if next < count { submit() }
            }
        }
        try Task.checkCancellation()
        let png = try await ArtworkRaster.shared.png(svg: plan.svg, images: images, width: width, height: height)
        if missing == 0 { cache.pages.setObject(png as NSData, forKey: key, cost: png.count) }
        return ArtworkResult(png: png, missing: missing)
    }

    private func load(_ resource: ArtworkPlan.Resource, client: ZakkaClient, thumbnail: Bool, edge: Int) async throws -> String {
        let key = "\(resource.asset.map { "asset:\($0)" } ?? resource.path ?? ""):\(thumbnail):\(edge)" as NSString
        let cache = caches.object(forKey: client)
        if let hit = cache?.media.object(forKey: key) { return hit as String }
        let uri = try await ArtworkMedia.fetch(resource, thumbnail: thumbnail, edge: edge) {
            try await client.data($0)
        }
        cache?.media.setObject(uri as NSString, forKey: key, cost: uri.utf8.count)
        return uri
    }
}
