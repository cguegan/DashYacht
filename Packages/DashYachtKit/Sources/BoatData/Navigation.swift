import Foundation

/// A position in degrees.
public struct Coordinate: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A flat local frame around a point, in metres: x to the east, y to the north.
/// Accurate enough for the short distances of collision avoidance (tens of nautical miles).
public struct LocalFrame: Sendable {
    public var origin: Coordinate
    private static let metresPerDegree = 1852.0 * 60

    public init(origin: Coordinate) {
        self.origin = origin
    }

    public func offset(of point: Coordinate) -> SIMD2<Double> {
        let east = (point.longitude - origin.longitude) * Self.metresPerDegree * cos(origin.latitude * .pi / 180)
        let north = (point.latitude - origin.latitude) * Self.metresPerDegree
        return SIMD2(east, north)
    }
}

/// Position and motion over ground of a vessel.
public struct Motion: Sendable, Equatable {
    /// Metres in a `LocalFrame`.
    public var position: SIMD2<Double>
    /// Speed over ground, m/s.
    public var speed: Double
    /// Course over ground, radians, true.
    public var course: Double

    public init(position: SIMD2<Double>, speed: Double, course: Double) {
        self.position = position
        self.speed = speed
        self.course = course
    }

    /// Velocity in metres per second, east and north.
    public var velocity: SIMD2<Double> {
        SIMD2(speed * sin(course), speed * cos(course))
    }
}

/// Closest point of approach between two vessels that keep their course and speed.
public struct ClosestApproach: Sendable, Equatable {
    /// Distance at the closest point, metres.
    public var distance: Double
    /// Time until the closest point, seconds. 0 when the vessels are already moving apart.
    public var time: TimeInterval
    /// Positions at that time, in the same frame as the input.
    public var ownPosition: SIMD2<Double>
    public var targetPosition: SIMD2<Double>

    public init(own: Motion, target: Motion) {
        let relativePosition = target.position - own.position
        let relativeVelocity = target.velocity - own.velocity
        let speedSquared = (relativeVelocity * relativeVelocity).sum()
        // Same velocity: the distance never changes. Negative time: the closest point is behind us.
        let t = speedSquared < 1e-9 ? 0 : max(0, -(relativePosition * relativeVelocity).sum() / speedSquared)

        time = t
        ownPosition = own.position + own.velocity * t
        targetPosition = target.position + target.velocity * t
        let gap = targetPosition - ownPosition
        distance = (gap * gap).sum().squareRoot()
    }
}

/// Angles that keep turning past 360°, so an animation always takes the shortest turn.
public enum ContinuousAngle {
    /// Returns `target` (degrees, any range) moved by whole turns to be as close as possible to `previous`.
    /// For example, from 359° to 1° gives 361°: a 2° turn, not 358° the other way.
    public static func nearest(to previous: Double, target: Double) -> Double {
        var delta = (target - previous).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        return previous + delta
    }
}
