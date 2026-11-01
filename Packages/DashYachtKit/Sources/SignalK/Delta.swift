import Foundation

/// A Signal K delta message: changes to one vessel (the `context`).
///
/// See https://signalk.org/specification/1.7.0/doc/data_model.html
public struct Delta: Sendable, Equatable, Decodable {
    /// `nil` means the own vessel ("self").
    public var context: String?
    public var updates: [Update]

    public init(context: String? = nil, updates: [Update]) {
        self.context = context
        self.updates = updates
    }

    public struct Update: Sendable, Equatable, Decodable {
        /// Source reference, for example `n2k.160` or `ttyUSB0.GP`.
        public var sourceRef: String?
        /// Time of the measurement, as sent by the server. Can be missing or wrong (bad clock on board).
        public var timestamp: Date?
        public var values: [PathValue]

        public init(sourceRef: String? = nil, timestamp: Date? = nil, values: [PathValue]) {
            self.sourceRef = sourceRef
            self.timestamp = timestamp
            self.values = values
        }

        private enum CodingKeys: String, CodingKey {
            case sourceRef = "$source", source, timestamp, values
        }

        private struct Source: Decodable {
            var label: String?
            var src: String?
            var talker: String?
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            values = try container.decodeIfPresent([PathValue].self, forKey: .values) ?? []
            timestamp = (try? container.decodeIfPresent(String.self, forKey: .timestamp)).flatMap { $0.flatMap(Self.parseDate) }
            if let ref = try container.decodeIfPresent(String.self, forKey: .sourceRef) {
                sourceRef = ref
            } else if let source = try? container.decodeIfPresent(Source.self, forKey: .source) {
                sourceRef = [source.label, source.src ?? source.talker]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: ".")
            }
        }

        /// Signal K timestamps are ISO 8601, with or without fractional seconds.
        static func parseDate(_ text: String) -> Date? {
            if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
                return date
            }
            return try? Date(text, strategy: .iso8601)
        }
    }

    public struct PathValue: Sendable, Equatable, Decodable {
        /// Dot-separated Signal K path, for example `navigation.speedOverGround`.
        public var path: String
        public var value: JSONValue

        public init(path: String, value: JSONValue) {
            self.path = path
            self.value = value
        }

        private enum CodingKeys: String, CodingKey { case path, value }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            value = try container.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
        }
    }
}
