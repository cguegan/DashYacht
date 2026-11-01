import Foundation
import Network

/// A Signal K server found on the local network with Bonjour.
public struct DiscoveredServer: Sendable, Hashable, Identifiable {
    public var name: String
    /// IPv4 address and port, for example `10.42.0.1:3000`. Can be used with `ServerAddress`.
    public var address: String
    public var id: String { name }
}

/// Finds Signal K servers that advertise `_signalk-ws._tcp` on the local network.
public enum ServerBrowser {
    public static func servers() -> AsyncStream<[DiscoveredServer]> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "DashYacht.ServerBrowser")
            let state = State()
            let browser = NWBrowser(for: .bonjour(type: "_signalk-ws._tcp", domain: nil), using: .tcp)

            browser.browseResultsChangedHandler = { results, _ in
                let names = Set(results.compactMap { serviceName($0.endpoint) })
                state.servers = state.servers.filter { names.contains($0.key) }
                continuation.yield(state.sorted)

                for result in results {
                    guard let name = serviceName(result.endpoint), state.servers[name] == nil,
                          !state.resolving.contains(name) else { continue }
                    state.resolving.insert(name)
                    resolve(result.endpoint, queue: queue) { address in
                        state.resolving.remove(name)
                        guard let address else { return }
                        state.servers[name] = DiscoveredServer(name: name, address: address)
                        continuation.yield(state.sorted)
                    }
                }
            }
            browser.start(queue: queue)
            continuation.onTermination = { _ in browser.cancel() }
        }
    }

    /// Mutable state, only used on the browser queue.
    private final class State: @unchecked Sendable {
        var servers: [String: DiscoveredServer] = [:]
        var resolving: Set<String> = []
        var sorted: [DiscoveredServer] { servers.values.sorted { $0.name < $1.name } }
    }

    private static func serviceName(_ endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { name } else { nil }
    }

    /// Bonjour gives a service name, not an address. Connecting to the service resolves it.
    /// IPv4 only, because IPv6 link-local addresses need an interface name in the URL.
    private static func resolve(_ endpoint: NWEndpoint, queue: DispatchQueue,
                                completion: @escaping @Sendable (String?) -> Void) {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)
        let done = Once()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var address: String?
                if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
                   case .ipv4(let ipv4) = host {
                    address = "\(ipv4):\(port.rawValue)"
                }
                connection.cancel()
                if done.claim() { completion(address) }
            case .failed, .cancelled:
                if done.claim() { completion(nil) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
    }

    private final class Once: @unchecked Sendable {
        private var claimed = false
        /// Only called on the browser queue.
        func claim() -> Bool {
            defer { claimed = true }
            return !claimed
        }
    }
}
