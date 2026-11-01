import Foundation
import Testing
import SignalK

/// Connects to a real Signal K server. Only runs when SIGNALK_TEST_ADDRESS is set,
/// for example `SIGNALK_TEST_ADDRESS=localhost:3000 swift test`.
struct LiveServerTests {
    static let address = ProcessInfo.processInfo.environment["SIGNALK_TEST_ADDRESS"]

    @Test(.enabled(if: address != nil), .timeLimit(.minutes(1)))
    func receivesHelloAndDeltas() async throws {
        let url = try #require(ServerAddress.streamURL(from: Self.address!))
        var connected = false
        var hello = false
        var deltas = 0
        for await event in SignalKClient.events(url: url) {
            switch event {
            case .status(.connected): connected = true
            case .status(.disconnected(let reason, _)), .status(.failed(let reason)):
                Issue.record("Connection failed: \(reason)")
                return
            case .message(.hello): hello = true
            case .message(.delta): deltas += 1
            default: break
            }
            if deltas >= 20 { break }
        }
        #expect(connected)
        #expect(hello)
        #expect(deltas >= 20)
    }
}
