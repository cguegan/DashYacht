import Foundation

/// A message received from a Signal K stream.
public enum Message: Sendable, Equatable {
    /// First message from a server. `selfContext` identifies the own vessel, for example
    /// `vessels.urn:mrn:imo:mmsi:230099999`.
    case hello(selfContext: String?)
    case delta(Delta)

    /// Decodes one stream message. Returns `nil` for messages DashYacht does not use.
    public static func decode(_ data: Data) -> Message? {
        let decoder = JSONDecoder()
        if let delta = try? decoder.decode(Delta.self, from: data), !delta.updates.isEmpty {
            return .delta(delta)
        }
        if let hello = try? decoder.decode(Hello.self, from: data), hello.version != nil {
            return .hello(selfContext: hello.selfContext)
        }
        return nil
    }

    private struct Hello: Decodable {
        var version: String?
        var selfContext: String?
        private enum CodingKeys: String, CodingKey { case version, selfContext = "self" }
    }
}

/// Events from any data source (Signal K server, replay file, and later NMEA sources).
public enum SourceEvent: Sendable, Equatable {
    case status(SourceStatus)
    case message(Message)
}

public enum SourceStatus: Sendable, Equatable {
    case connecting
    case connected
    /// The connection failed or closed. The source tries again after `retryIn` seconds.
    case disconnected(reason: String, retryIn: Int)
    /// The source has stopped and will not try again (for example, a replay file cannot be read).
    case failed(reason: String)
}
