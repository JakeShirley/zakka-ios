import Foundation
import Testing
@testable import ZakkaCore

@Test func movingOneLayerPreservesUnknownEffectsAndOtherLayers() throws {
    let raw = #"{"version":1,"future":{"profile":"warm"},"layers":[{"id":"a","kind":"photo","effect":{"test":[true,null,0.2]},"x":1},{"id":"b","locked":true,"x":2}]}"#
    let previous = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    let next = PageEditing.changing("a", in: previous) { $0["x"] = 42 }
    let saved = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(next))
    #expect(saved["layers"].items[0]["x"] == 42)
    #expect(saved["layers"].items[0]["effect"] == previous["layers"].items[0]["effect"])
    #expect(saved["future"] == previous["future"])
    #expect(PageEditing.changing("b", in: saved) { $0["x"] = 100 } == saved)
}

@Test func newPhotoUsesPageCoordinates() {
    let doc = PageEditing.blank(width: 3000, height: 1500)
    let layer = PageEditing.newLayer(kind: "photo", document: doc, content: "asset_test")
    #expect(layer["assetId"] == "asset_test")
    #expect(layer["width"] == 2100)
    #expect(layer["height"] == 750)
}
