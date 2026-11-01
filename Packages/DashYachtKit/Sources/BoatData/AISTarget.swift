import Foundation

/// Another vessel, from AIS.
public struct AISTarget: Sendable, Equatable, Identifiable {
    /// Signal K context, for example `vessels.urn:mrn:imo:mmsi:230035780`.
    public var id: String
    public var name: String?
    public var position: Coordinate
    /// m/s, `nil` when not sent.
    public var speed: Double?
    /// Radians, true, `nil` when not sent.
    public var course: Double?
    /// Time since the last position report, seconds.
    public var age: TimeInterval

    public var mmsi: String? {
        id.split(separator: ":").last.map(String.init).flatMap { $0.allSatisfy(\.isNumber) ? $0 : nil }
    }
}
