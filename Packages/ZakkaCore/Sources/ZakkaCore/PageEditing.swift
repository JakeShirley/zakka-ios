import Foundation

public enum PageEditing {
    public static func blank(width: JSONValue, height: JSONValue) -> JSONValue {
        ["version": 1, "canvas": ["width": width, "height": height, "backgroundColor": "#fffdf7"], "layers": []]
    }

    public static func newLayer(kind: String, document: JSONValue, content: String) -> JSONValue {
        let w = document["canvas"]["width"].double, h = document["canvas"]["height"].double
        var layer: JSONValue = ["id": .string(UUID().uuidString), "kind": .string(kind), "locked": false, "opacity": 1,
                                "x": .number(w * 0.15), "y": .number(h * 0.22), "width": .number(w * 0.7),
                                "height": .number(h * 0.5), "rotation": 0]
        switch kind {
        case "text":
            layer["text"] = .string(content); layer["fontFamily"] = "Georgia"; layer["align"] = "left"
            layer["color"] = "#263b32"; layer["fontSize"] = .number(min(140,w/20)); layer["height"] = .number(h * 0.22)
        case "photo":
            layer["assetId"] = .string(content); layer["fit"] = "cover"
        case "sticker":
            layer["stickerId"] = .string(content); layer["width"] = .number(w * 0.2); layer["height"] = layer["width"]
        case "washiTape":
            layer["width"] = .number(w * 0.42); layer["height"] = .number(w * 0.075)
            layer["outline"] = "torn"
            layer["pattern"] = ["kind": "polkaDot", "primaryColor": "#fffdf7", "secondaryColor": "#79a9a4"]
        default: break
        }
        return layer
    }

    public static func changing(_ id: String, in document: JSONValue, update: (inout JSONValue) -> Void) -> JSONValue {
        var result = document
        var layers = document["layers"].items
        guard let i = layers.firstIndex(where: { $0.id == id }), layers[i]["locked"] != true else { return result }
        update(&layers[i])
        result["layers"] = .array(layers)
        return result
    }
}
