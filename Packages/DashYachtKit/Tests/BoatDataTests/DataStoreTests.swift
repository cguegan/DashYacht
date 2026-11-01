import Foundation
import Testing
import SignalK
@testable import BoatData

@MainActor
struct DataStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func delta(_ path: String, _ value: JSONValue, context: String? = nil) -> Message {
        .delta(Delta(context: context, updates: [.init(values: [.init(path: path, value: value)])]))
    }

    @Test("A value becomes stale when updates stop, so a frozen number never looks live")
    func staleness() throws {
        let store = DataStore()
        store.apply(delta("environment.depth.belowKeel", .number(3.2)), receivedAt: t0)

        let fresh = try #require(store.reading("environment.depth.belowKeel", now: t0.addingTimeInterval(5)))
        #expect(fresh.isLive)
        let old = try #require(store.reading("environment.depth.belowKeel", now: t0.addingTimeInterval(6)))
        #expect(old.freshness == .stale(age: 6))
        #expect(old.sample.value == .number(3.2))
    }

    @Test("An AIS target never replaces the own position")
    func otherVesselsIgnored() throws {
        let store = DataStore()
        store.apply(.hello(selfContext: "vessels.urn:mrn:imo:mmsi:111111111"), receivedAt: t0)
        store.apply(delta("navigation.speedOverGround", .number(3), context: "vessels.urn:mrn:imo:mmsi:111111111"), receivedAt: t0)
        store.apply(delta("navigation.speedOverGround", .number(9), context: "vessels.urn:mrn:imo:mmsi:222222222"), receivedAt: t0)
        store.apply(delta("navigation.speedOverGround", .number(4), context: "vessels.self"), receivedAt: t0)

        #expect(store.reading("navigation.speedOverGround", now: t0)?.sample.value == .number(4))
    }

    @Test("A live alternative is preferred over a stale first choice")
    func fallback() throws {
        let store = DataStore()
        store.apply(delta("environment.depth.belowKeel", .number(2.0)), receivedAt: t0)
        store.apply(delta("environment.depth.belowTransducer", .number(2.5)), receivedAt: t0.addingTimeInterval(10))

        let paths = ["environment.depth.belowKeel", "environment.depth.belowTransducer"]
        #expect(store.reading(paths, now: t0.addingTimeInterval(1))?.path == "environment.depth.belowKeel")
        #expect(store.reading(paths, now: t0.addingTimeInterval(11))?.path == "environment.depth.belowTransducer")
        // When all are stale, the most recent value is shown (greyed by the UI).
        let allStale = store.reading(paths, now: t0.addingTimeInterval(60))
        #expect(allStale?.path == "environment.depth.belowTransducer")
        #expect(allStale?.isLive == false)
    }

    @Test("A wildcard finds batteries whatever their id")
    func wildcard() {
        let store = DataStore()
        store.apply(delta("electrical.batteries.house.voltage", .number(12.6)), receivedAt: t0)
        store.apply(delta("electrical.batteries.house.current", .number(-3)), receivedAt: t0)
        #expect(store.reading("electrical.batteries.*.voltage", now: t0)?.path == "electrical.batteries.house.voltage")
    }

    @Test("Changing the data source starts from an empty store")
    func reset() {
        let store = DataStore()
        store.apply(delta("navigation.speedOverGround", .number(3)), receivedAt: t0)
        store.reset()
        #expect(store.reading("navigation.speedOverGround", now: t0) == nil)
    }
}
