import Foundation
import SignalK

/// RPM and gear of one engine, from Signal K `propulsion.<id>.revolutions` and `propulsion.<id>.transmission.gear`.
public struct EngineState: Equatable, Sendable {
    public enum Gear: String, Sendable {
        case forward, neutral, reverse
    }

    /// Revolutions per minute, never negative.
    public var rpm: Double
    /// `nil` when the engine does not send its gear.
    public var gear: Gear?

    /// `revolutions` is in Hz (Signal K). `nil` when there is no number.
    public init?(revolutions: JSONValue?, gear: JSONValue?) {
        guard let hertz = revolutions?.number else { return nil }
        rpm = max(0, hertz * 60)
        self.gear = gear?.string.flatMap { Gear(rawValue: $0.lowercased()) }
    }

    /// For the band: positive ahead, negative astern, 0 in neutral (the engine turns but does not drive).
    /// Without gear data the direction is unknown and the value counts as ahead.
    public var signedRPM: Double {
        switch gear {
        case .reverse: -rpm
        case .neutral: 0
        case .forward, nil: rpm
        }
    }

    /// "1450 F", "1200 R", "750 N", or "1450" without gear data.
    public var text: String {
        let value = String(format: "%.0f", rpm)
        switch gear {
        case .forward: return value + " F"
        case .reverse: return value + " R"
        case .neutral: return value + " N"
        case nil: return value
        }
    }
}
