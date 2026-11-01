import Foundation
import Testing
@testable import SignalK

struct MessageTests {
    @Test("Server delta with $source and a position object is decoded")
    func decodesDelta() throws {
        let json = """
        {"context":"vessels.urn:mrn:imo:mmsi:234567890","updates":[{"$source":"n2k.160",
        "timestamp":"2014-08-15T19:00:00.042Z","values":[
        {"path":"navigation.speedOverGround","value":3.14},
        {"path":"navigation.position","value":{"latitude":59.725,"longitude":24.7366}}]}]}
        """
        guard case .delta(let delta)? = Message.decode(Data(json.utf8)) else {
            Issue.record("Not decoded as a delta")
            return
        }
        let update = try #require(delta.updates.first)
        #expect(delta.context == "vessels.urn:mrn:imo:mmsi:234567890")
        #expect(update.sourceRef == "n2k.160")
        #expect(abs((update.timestamp?.timeIntervalSince1970 ?? 0) - 1_408_129_200.042) < 0.0005)
        #expect(update.values[0].value == .number(3.14))
        #expect(update.values[1].value["latitude"] == .number(59.725))
    }

    @Test("A source object without $source still identifies the device")
    func sourceObject() {
        let json = #"{"updates":[{"source":{"label":"","type":"NMEA2000","pgn":129029,"src":"160"},"values":[{"path":"a","value":1}]}]}"#
        guard case .delta(let delta)? = Message.decode(Data(json.utf8)) else {
            Issue.record("Not decoded as a delta")
            return
        }
        #expect(delta.updates[0].sourceRef == "160")
    }

    @Test("The hello message gives the own vessel context")
    func hello() {
        let json = #"{"name":"signalk-server","version":"2.35.1","self":"vessels.urn:mrn:imo:mmsi:234567890","roles":["master"]}"#
        #expect(Message.decode(Data(json.utf8)) == .hello(selfContext: "vessels.urn:mrn:imo:mmsi:234567890"))
    }

    @Test("Unknown and broken messages are ignored, not fatal", arguments: [
        #"{"requestId":"1","state":"COMPLETED"}"#,
        #"{"updates":[{"values":[{"path":"a","value":1}]"#,
        "not json",
    ])
    func ignoresOthers(json: String) {
        #expect(Message.decode(Data(json.utf8)) == nil)
    }
}
