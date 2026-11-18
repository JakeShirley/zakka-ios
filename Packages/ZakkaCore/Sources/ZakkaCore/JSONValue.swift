import Foundation

/// Keep unedited document properties, including layers and effects introduced by newer servers.
public enum JSONValue: Sendable, Codable, Equatable, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null

    public init(dictionaryLiteral elements: (String, Self)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
    public init(arrayLiteral elements: Self...) { self = .array(elements) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(Double.self) { self = .number(x) }
        else if let x = try? c.decode(String.self) { self = .string(x) }
        else if let x = try? c.decode([Self].self) { self = .array(x) }
        else { self = .object(try c.decode([String: Self].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(_ key: String) -> Self {
        get { if case let .object(v) = self { return v[key] ?? .null }; return .null }
        set { if case var .object(v) = self { v[key] = newValue; self = .object(v) } }
    }
    public var text: String { if case let .string(v) = self { return v }; return "" }
    public var double: Double { if case let .number(v) = self { return v }; return 0 }
    public var items: [Self] { if case let .array(v) = self { return v }; return [] }
    public var id: String { self["id"].text }
    public var title: String { self["title"].text }
}
