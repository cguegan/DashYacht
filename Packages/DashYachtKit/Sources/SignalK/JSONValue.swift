/// Any JSON value. Signal K values can be numbers, strings, objects (for example a position) or null.
public enum JSONValue: Sendable, Equatable, Decodable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public var number: Double? {
        if case .number(let value) = self { value } else { nil }
    }

    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }
}
