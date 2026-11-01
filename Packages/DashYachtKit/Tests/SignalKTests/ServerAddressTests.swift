import Testing
import SignalK

// Users type addresses in many forms. All must lead to the stream of the own vessel.
struct ServerAddressTests {
    @Test(arguments: [
        ("openplotter.local", "ws://openplotter.local:3000/signalk/v1/stream?subscribe=self"),
        (" 10.42.0.1:3000 ", "ws://10.42.0.1:3000/signalk/v1/stream?subscribe=self"),
        ("http://openplotter.local:8080/admin", "ws://openplotter.local:8080/signalk/v1/stream?subscribe=self"),
        ("https://boat.local", "wss://boat.local:3443/signalk/v1/stream?subscribe=self"),
        ("ws://boat.local/signalk/v1/stream", "ws://boat.local:3000/signalk/v1/stream?subscribe=self"),
    ])
    func validAddresses(input: String, expected: String) {
        #expect(ServerAddress.streamURL(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://boat.local", "http://"])
    func invalidAddresses(input: String) {
        #expect(ServerAddress.streamURL(from: input) == nil)
    }
}
