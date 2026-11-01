import Foundation

/// Coastline from the shoreline file made by `Scripts/make-shoreline.py` (GSHHG, full resolution).
/// The world is cut into 1° × 1° cells; only the cells near the boat are decoded.
/// For display only: not precise enough for navigation.
public struct Shoreline: Sendable {
    public enum ReadError: Error { case notAShorelineFile, unsupportedVersion(Int), damaged }

    /// South-west corner of a cell, in whole degrees.
    public struct Cell: Hashable, Sendable {
        public var south: Int
        public var west: Int

        public init(south: Int, west: Int) {
            self.south = south
            self.west = west
        }
    }

    private let data: Data
    private let index: [Cell: Range<Int>]
    private static let unitsPerDegree = 16384.0

    public init(data: Data) throws {
        guard data.count >= 9, data.prefix(4) == Data("DYSL".utf8) else { throw ReadError.notAShorelineFile }
        let bytes = [UInt8](data)
        guard bytes[4] == 1 else { throw ReadError.unsupportedVersion(Int(bytes[4])) }
        let count = Int(Self.uint32(bytes, at: 5))
        guard data.count >= 9 + 12 * count else { throw ReadError.damaged }
        var index: [Cell: Range<Int>] = [:]
        for entry in 0..<count {
            let at = 9 + 12 * entry
            let offset = Int(Self.uint32(bytes, at: at + 4)), length = Int(Self.uint32(bytes, at: at + 8))
            guard offset + length <= data.count else { throw ReadError.damaged }
            let cell = Cell(south: Int(Int16(bitPattern: Self.uint16(bytes, at: at))),
                            west: Int(Int16(bitPattern: Self.uint16(bytes, at: at + 2))))
            index[cell] = offset..<(offset + length)
        }
        self.data = data
        self.index = index
    }

    public var cellCount: Int { index.count }

    /// Cells that can contain coast within `radius` metres of `center`. Near the poles the box is wider.
    public func cells(around center: Coordinate, radius: Double) -> [Cell] {
        let latitudeSpan = radius / (1852 * 60)
        let longitudeSpan = latitudeSpan / max(cos(center.latitude * .pi / 180), 0.01)
        let south = Int((center.latitude - latitudeSpan).rounded(.down)), north = Int((center.latitude + latitudeSpan).rounded(.down))
        let west = Int((center.longitude - longitudeSpan).rounded(.down)), east = Int((center.longitude + longitudeSpan).rounded(.down))
        var cells: [Cell] = []
        for latitude in max(-90, south)...min(89, north) {
            for longitude in west...east {
                // Across the antimeridian, wrap to -180…179.
                let wrapped = ((longitude + 180) % 360 + 360) % 360 - 180
                let cell = Cell(south: latitude, west: wrapped)
                if index[cell] != nil { cells.append(cell) }
            }
        }
        return cells
    }

    /// Lines of one cell, or `[]` when the cell has no coast. Decoding takes a few milliseconds:
    /// keep the result instead of calling this for every frame.
    public func lines(in cell: Cell) throws -> [[Coordinate]] {
        guard let range = index[cell] else { return [] }
        // Raw DEFLATE, which Apple calls "zlib".
        guard let raw = try? (data.subdata(in: range) as NSData).decompressed(using: .zlib) as Data else {
            throw ReadError.damaged
        }
        var reader = VarintReader(bytes: [UInt8](raw))
        var lines: [[Coordinate]] = []
        let lineCount = try reader.next()
        lines.reserveCapacity(lineCount)
        for _ in 0..<lineCount {
            let pointCount = try reader.next()
            var line: [Coordinate] = []
            line.reserveCapacity(pointCount)
            var x = 0, y = 0
            for _ in 0..<pointCount {
                x += try reader.next()
                y += try reader.next()
                line.append(Coordinate(latitude: Double(cell.south) + Double(y) / Self.unitsPerDegree,
                                       longitude: Double(cell.west) + Double(x) / Self.unitsPerDegree))
            }
            lines.append(line)
        }
        return lines
    }

    private static func uint16(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[index + $1]) << (8 * $1) }
    }
}

/// Zigzag LEB128 numbers, as written by the conversion script.
private struct VarintReader {
    let bytes: [UInt8]
    var position = 0

    mutating func next() throws -> Int {
        var value: UInt64 = 0, shift: UInt64 = 0
        while true {
            guard position < bytes.count, shift < 64 else { throw Shoreline.ReadError.damaged }
            let byte = bytes[position]
            position += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { break }
            shift += 7
        }
        return Int(Int64(bitPattern: value >> 1) ^ -Int64(bitPattern: value & 1))
    }
}
