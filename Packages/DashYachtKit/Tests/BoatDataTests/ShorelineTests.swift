import Foundation
import Testing
@testable import BoatData

/// Reads Resources/shoreline-fixture.dysl, made by Scripts/make-shoreline-fixture.py with the real
/// conversion script, so these tests check that the Swift reader and the Python writer agree.
struct ShorelineTests {
    private func fixture() throws -> Shoreline {
        let url = try #require(Bundle.module.url(forResource: "shoreline-fixture", withExtension: "dysl",
                                                 subdirectory: "Resources"))
        return try Shoreline(data: Data(contentsOf: url))
    }

    @Test("An island on the corner of four cells is drawn whole: every cell has its part, without gaps")
    func islandAcrossCells() throws {
        let shoreline = try fixture()
        let cells = shoreline.cells(around: Coordinate(latitude: 60, longitude: 25), radius: 1852 * 5)
        #expect(Set(cells) == [Shoreline.Cell(south: 59, west: 24), Shoreline.Cell(south: 59, west: 25),
                               Shoreline.Cell(south: 60, west: 24), Shoreline.Cell(south: 60, west: 25)])
        let points = try cells.flatMap { try shoreline.lines(in: $0).flatMap { $0 } }
        // Every point lies on the square's edge, within the stored precision (1/16384°).
        let precision = 1.0 / 16384
        for point in points {
            let onLatitudeEdge = abs(point.latitude - 59.9) < precision || abs(point.latitude - 60.1) < precision
            let onLongitudeEdge = abs(point.longitude - 24.9) < precision || abs(point.longitude - 25.1) < precision
            #expect(onLatitudeEdge || onLongitudeEdge)
        }
        // All four corners are there, so no side is missing.
        for (latitude, longitude) in [(59.9, 24.9), (59.9, 25.1), (60.1, 25.1), (60.1, 24.9)] {
            #expect(points.contains { abs($0.latitude - latitude) < precision && abs($0.longitude - longitude) < precision })
        }
    }

    @Test("Lakes are left out: at sea only the coast matters")
    func lakesLeftOut() throws {
        let shoreline = try fixture()
        #expect(shoreline.cells(around: Coordinate(latitude: 10.3, longitude: 10.3), radius: 1852 * 5).isEmpty)
        #expect(try shoreline.lines(in: Shoreline.Cell(south: 10, west: 10)).isEmpty)
    }

    @Test("Near the antimeridian, the cells on the other side are found too")
    func antimeridian() throws {
        let shoreline = try fixture()
        // From 179.9° W (-179.9), the island at 179.8° E is 0.1° to the west, across the antimeridian.
        let cells = shoreline.cells(around: Coordinate(latitude: 0.25, longitude: -179.9), radius: 1852 * 30)
        #expect(cells.contains(Shoreline.Cell(south: 0, west: 179)))
    }

    @Test("A file that is not a shoreline file is refused, not misread")
    func wrongFile() {
        #expect(throws: Shoreline.ReadError.self) { try Shoreline(data: Data("not a shoreline".utf8)) }
    }
}
