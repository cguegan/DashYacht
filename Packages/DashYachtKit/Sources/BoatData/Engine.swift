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

    /// RPM only, "1450". The band shows the gear: up ahead, down astern, no bar in neutral.
    public var text: String {
        String(format: "%.0f", rpm)
    }
}
