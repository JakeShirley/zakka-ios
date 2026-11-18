import Foundation
import JavaScriptCore

struct ArtworkPlan: Decodable, Sendable {
    struct Resource: Decodable, Sendable {
        var asset: String?
        var path: String?
        var glyph: String?
    }
    let svg: String
    let resources: [Resource]
    let omitted: Int
}

enum ArtworkError: Error { case missingBundle, invalidDocument, imageUnavailable, tooLarge }

actor ArtworkEngine {
    static let shared = ArtworkEngine()
    private let directory: URL?
    private var context: JSContext?
    private var hasWorld = false

    init(directory: URL? = Bundle.main.url(forResource: "ZakkaArtwork", withExtension: "bundle")) {
        self.directory = directory
    }

    func plan(json: Data, maps: Bool, editor: Bool, thumbnail: Bool) throws -> ArtworkPlan {
        try Task.checkCancellation()
        guard let directory else { throw ArtworkError.missingBundle }
        let js: JSContext
        if let context {
            js = context
        } else {
            guard let fresh = JSContext() else { throw ArtworkError.missingBundle }
            let script = try String(contentsOf: directory.appendingPathComponent("engine.js"), encoding: .utf8)
            fresh.evaluateScript(script)
            guard fresh.exception == nil else { throw ArtworkError.missingBundle }
            context = fresh
            js = fresh
        }
        defer { js.exception = nil }
        let bridge = js.objectForKeyedSubscript("ZakkaArtwork")
        if maps && !hasWorld {
            let world = try String(contentsOf: directory.appendingPathComponent("world-50m.topojson"), encoding: .utf8)
            bridge?.invokeMethod("installWorld", withArguments: [world])
            guard js.exception == nil else { throw ArtworkError.missingBundle }
            hasWorld = true
        }
        let value = bridge?.invokeMethod("plan", withArguments: [String(decoding: json, as: UTF8.self), editor, thumbnail])
        guard js.exception == nil, let string = value?.toString() else { throw ArtworkError.invalidDocument }
        return try JSONDecoder().decode(ArtworkPlan.self, from: Data(string.utf8))
    }
}
