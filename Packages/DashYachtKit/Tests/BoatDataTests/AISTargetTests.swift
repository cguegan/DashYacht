import Foundation
import Testing
import SignalK
@testable import BoatData

@MainActor
struct AISTargetTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let other = "vessels.urn:mrn:imo:mmsi:230099999"

    private func delta(_ context: String?, _ values: [(String, JSONValue)]) -> Message {
        .delta(Delta(context: context, updates: [.init(values: values.map { .init(path: $0.0, value: $0.1) })]))
    }

    private let position: JSONValue = .object(["latitude": .number(59.7), "longitude": .number(24.7)])

    @Test("AIS targets are kept apart from own data, with name, speed and course")
    func target() throws {
        let store = DataStore()
        store.apply(delta(other, [
            ("navigation.position", position),
            ("navigation.speedOverGround", .number(3)),
            ("navigation.courseOverGroundTrue", .number(1)),
            ("", .object(["name": .string("SEA BIRD")])),
        ]), receivedAt: t0)

        let target = try #require(store.aisTargets(now: t0).first)
        #expect(target.mmsi == "230099999")
        #expect(target.name == "SEA BIRD")
        #expect(target.speed == 3 && target.course == 1)
        #expect(store.reading("navigation.position", now: t0) == nil)
    }

    @Test("The own AIS transponder is not shown as a target")
    func ownTransponder() {
        let store = DataStore()
        store.apply(.hello(selfContext: other), receivedAt: t0)
        store.apply(delta(other, [("navigation.position", position)]), receivedAt: t0)
        #expect(store.aisTargets(now: t0).isEmpty)
    }

    @Test("A target without reports for 10 minutes is no longer shown")
    func lostTarget() {
        let store = DataStore()
        store.apply(delta(other, [("navigation.position", position)]), receivedAt: t0)
        #expect(store.aisTargets(now: t0.addingTimeInterval(600)).count == 1)
        #expect(store.aisTargets(now: t0.addingTimeInterval(601)).isEmpty)
    }

    @Test("Base stations and aids to navigation are not vessels")
    func notVessels() {
        let store = DataStore()
        store.apply(delta("shore.basestations.urn:mrn:imo:mmsi:002300048", [("navigation.position", position)]), receivedAt: t0)
        store.apply(delta("atons.urn:mrn:imo:mmsi:992761001", [("navigation.position", position)]), receivedAt: t0)
        #expect(store.aisTargets(now: t0).isEmpty)
    }
}
