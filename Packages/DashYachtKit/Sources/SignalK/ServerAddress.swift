import Foundation

/// Converts what a user types ("openplotter.local", "10.42.0.1:3000", "https://boat.local")
/// into the Signal K WebSocket stream URL.
public enum ServerAddress {
    /// Default ports of the Signal K server: 3000 (HTTP/WS) and 3443 (HTTPS/WSS).
    public static let defaultPort = 3000
    public static let defaultSecurePort = 3443

    /// Returns `nil` when the text does not contain a usable host name.
    public static func streamURL(from text: String) -> URL? {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        if !input.contains("://") { input = "ws://" + input }

        guard var components = URLComponents(string: input),
              let host = components.host, !host.isEmpty else { return nil }

        let secure: Bool
        switch components.scheme?.lowercased() {
        case "ws", "http": secure = false
        case "wss", "https": secure = true
        default: return nil
        }

        components.scheme = secure ? "wss" : "ws"
        components.port = components.port ?? (secure ? defaultSecurePort : defaultPort)
        components.path = "/signalk/v1/stream"
        components.queryItems = [URLQueryItem(name: "subscribe", value: "self")]
        return components.url
    }
}
