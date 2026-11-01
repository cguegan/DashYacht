import Foundation
import Testing
import SignalK
@testable import BoatData

@MainActor
struct InstrumentTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func delta(_ path: String, _ value: JSONValue, source: String?) -> Message {
        .delta(Delta(updates: [.init(sourceRef: source, values: [.init(path: path, value: value)])]))
    }

    private func reading(_ path: String, _ value: JSONValue) -> Reading {
        Reading(path: path, sample: Sample(value: value, sourceRef: nil, receivedAt: t0), freshness: .live)
    }

    @Test("A chosen source keeps its own value when another source sends the same path")
    func chosenSource() throws {
        let store = DataStore()
        store.apply(delta("navigation.speedThroughWater", .number(3.3), source: "115"), receivedAt: t0)
        store.apply(delta("navigation.speedThroughWater", .number(9.9), source: "160"), receivedAt: t0.addingTimeInterval(0.5))

        let log115 = SourceSelection(path: "navigation.speedThroughWater", sourceRef: "115")
        #expect(store.reading(log115, now: t0.addingTimeInterval(1))?.sample.value == .number(3.3))
        #expect(store.sources(for: Instrument.speedThroughWater.paths).map(\.sourceRef) == ["115", "160"])
    }

    @Test("A chosen source that stops sending turns stale, even when another source is still live")
    func chosenSourceStale() throws {
        let store = DataStore()
        store.apply(delta("navigation.speedThroughWater", .number(3.3), source: "115"), receivedAt: t0)
        store.apply(delta("navigation.speedThroughWater", .number(3.4), source: "160"), receivedAt: t0.addingTimeInterval(10))

        let log115 = SourceSelection(path: "navigation.speedThroughWater", sourceRef: "115")
        #expect(store.reading(log115, now: t0.addingTimeInterval(10))?.isLive == false)
    }

    @Test("Sources of wildcard paths are listed per battery")
    func wildcardSources() {
        let store = DataStore()
        store.apply(delta("electrical.batteries.house.voltage", .number(12.6), source: "129"), receivedAt: t0)
        store.apply(delta("electrical.batteries.start.voltage", .number(12.9), source: "129"), receivedAt: t0)
        #expect(store.sources(for: Instrument.batteryVoltage.paths).map(\.path)
            == ["electrical.batteries.house.voltage", "electrical.batteries.start.voltage"])
    }

    @Test("Changing the instrument of a card drops the source and unit of the old one")
    func changeInstrument() {
        var card = CardSettings(instrument: .depth,
                                source: SourceSelection(path: "environment.depth.belowKeel", sourceRef: "115"),
                                unit: .feet)
        card.change(to: .speedOverGround)
        #expect(card.instrument == .speedOverGround)
        #expect(card.source == nil)
        #expect(card.unit == nil)
    }

    @Test("A saved dashboard is read back the same after a restart")
    func savedSettings() throws {
        let cards = [
            CardSettings(instrument: .speedThroughWater,
                         source: SourceSelection(path: "navigation.speedThroughWater", sourceRef: "160"),
                         unit: .kilometresPerHour),
            CardSettings(instrument: .position),
        ]
        let data = try JSONEncoder().encode(cards)
        #expect(try JSONDecoder().decode([CardSettings].self, from: data) == cards)
    }

    @Test("Values are converted to the chosen unit")
    func units() {
        let speed = reading("navigation.speedOverGround", .number(5))
        #expect(Instrument.speedOverGround.value(of: speed, unit: .knots)?.lines == ["9.7"])
        #expect(Instrument.speedOverGround.value(of: speed, unit: .kilometresPerHour)?.lines == ["18.0"])
        #expect(Instrument.speedOverGround.value(of: speed, unit: .kilometresPerHour)?.unit == "km/h")

        let depth = reading("environment.depth.belowKeel", .number(10))
        #expect(Instrument.depth.value(of: depth, unit: .feet)?.lines == ["32.8"])
        #expect(Instrument.depth.value(of: depth, unit: .fathoms)?.lines == ["5.5"])

        let water = reading("environment.water.temperature", .number(293.15))
        #expect(Instrument.waterTemperature.value(of: water, unit: .fahrenheit)?.lines == ["68.0"])
    }

    @Test("A unit that does not apply to the instrument falls back to its default, never to a wrong conversion")
    func wrongUnit() {
        let speed = reading("navigation.speedOverGround", .number(5))
        #expect(Instrument.speedOverGround.value(of: speed, unit: .feet) == InstrumentValue(lines: ["9.7"], unit: "kts"))
    }

    @Test("Heading shows whether it is true or magnetic, from the path that was used")
    func headingReference() {
        let magnetic = reading("navigation.headingMagnetic", .number(.pi))
        #expect(Instrument.heading.value(of: magnetic, unit: nil) == InstrumentValue(lines: ["180°"], unit: "M"))
    }

    @Test("Position has one line per coordinate, in the chosen format")
    func position() {
        let position = reading("navigation.position", .object(["latitude": .number(59.7250108), "longitude": .number(24.736677)]))
        #expect(Instrument.position.value(of: position, unit: nil)?.lines == ["59°43.501′ N", "024°44.201′ E"])
        #expect(Instrument.position.value(of: position, unit: .degreesMinutesSeconds)?.lines
            == ["59°43′30.0″ N", "024°44′12.0″ E"])
        #expect(Instrument.position.value(of: position, unit: .decimalDegrees)?.lines == ["59.72501° N", "24.73668° E"])
    }

    @Test("Degrees, minutes, seconds never show 60 seconds")
    func secondsRollOver() {
        #expect(Format.latitude(10.99999, format: .degreesMinutesSeconds) == "11°00′00.0″ N")
    }
}
