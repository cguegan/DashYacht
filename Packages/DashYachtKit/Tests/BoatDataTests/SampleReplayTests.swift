import Foundation
import Testing
import SignalK
@testable import BoatData

/// Runs the recorded sample (real NMEA 2000 data, converted by Signal K) through the store,
/// to check that every value on the default dashboard is found and has a sensible range.
@MainActor
struct SampleReplayTests {
    @Test func dashboardValuesFromRealData() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().appending(path: "../../../../App/SampleData/aava-n2k-3min.jsonl")
        let file = ReplayFile(data: try Data(contentsOf: url))
        let store = DataStore()
        let t0 = Date(timeIntervalSince1970: 0)
        for entry in file.entries {
            store.apply(.delta(entry.delta), receivedAt: t0.addingTimeInterval(Double(entry.offset.components.seconds)))
        }
        let end = t0.addingTimeInterval(Double(file.entries.last!.offset.components.seconds))

        func value(_ paths: String...) -> Double? {
            store.reading(paths, now: end)?.sample.value.number
        }

        let sog = try #require(value("navigation.speedOverGround"))
        #expect((0...10).contains(sog), "SOG \(sog) m/s")
        let depth = try #require(value("environment.depth.belowKeel", "environment.depth.belowTransducer"))
        #expect((0.5...200).contains(depth), "Depth \(depth) m")
        let water = try #require(value("environment.water.temperature"))
        // Signal K uses kelvin. The sensor in this recording reports a constant 313.15 K (40 °C).
        #expect((250...330).contains(water), "Water \(water) K")
        let volts = try #require(value("electrical.batteries.*.voltage"))
        #expect((10...16).contains(volts), "Battery \(volts) V")
        #expect(value("navigation.headingTrue") != nil)
        #expect(value("navigation.courseOverGroundTrue") != nil)
        #expect(value("environment.wind.angleApparent") != nil)

        // The sample contains AIS targets. The own position must stay near the Aava in the Gulf of Finland.
        let position = try #require(store.reading("navigation.position", now: end)?.sample.value)
        let lat = try #require(position["latitude"]?.number)
        let lon = try #require(position["longitude"]?.number)
        #expect(abs(lat - 59.72) < 0.1 && abs(lon - 24.73) < 0.1, "Position \(lat), \(lon)")
    }
}
