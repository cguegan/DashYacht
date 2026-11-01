import Testing
import BoatData

// CPA and TCPA decide whether a ship is a danger. A wrong sign or a wrong time
// can hide a collision course, so each situation a skipper meets is checked.
struct ClosestApproachTests {
    private let knots5 = 5 * 1852.0 / 3600

    private func motion(_ east: Double, _ north: Double, speed: Double, courseDegrees: Double) -> Motion {
        Motion(position: SIMD2(east, north), speed: speed, course: courseDegrees * .pi / 180)
    }

    @Test("Head-on: collision halfway, after the time to close the gap")
    func headOn() {
        let cpa = ClosestApproach(own: motion(0, 0, speed: knots5, courseDegrees: 0),
                                  target: motion(0, 1852, speed: knots5, courseDegrees: 180))
        #expect(cpa.distance < 0.001)
        #expect(abs(cpa.time - 1852 / (2 * knots5)) < 0.001) // 6 minutes
        #expect(abs(cpa.ownPosition.y - 926) < 0.001)
    }

    @Test("Crossing from starboard on a collision course")
    func crossing() {
        let cpa = ClosestApproach(own: motion(0, 0, speed: 5, courseDegrees: 0),
                                  target: motion(1000, 1000, speed: 5, courseDegrees: 270))
        #expect(cpa.distance < 0.001)
        #expect(abs(cpa.time - 200) < 0.001)
    }

    @Test("Passing on opposite courses: CPA is the side distance, when abeam")
    func passing() {
        let cpa = ClosestApproach(own: motion(0, 0, speed: 5, courseDegrees: 0),
                                  target: motion(500, 2000, speed: 5, courseDegrees: 180))
        #expect(abs(cpa.distance - 500) < 0.001)
        #expect(abs(cpa.time - 200) < 0.001)
    }

    @Test("Moving apart: the closest point is now, not in the past")
    func diverging() {
        let cpa = ClosestApproach(own: motion(0, 0, speed: 5, courseDegrees: 0),
                                  target: motion(0, -1000, speed: 5, courseDegrees: 180))
        #expect(cpa.time == 0)
        #expect(abs(cpa.distance - 1000) < 0.001)
    }

    @Test("Same course and speed: the distance never changes")
    func parallel() {
        let cpa = ClosestApproach(own: motion(0, 0, speed: 5, courseDegrees: 45),
                                  target: motion(300, 400, speed: 5, courseDegrees: 45))
        #expect(cpa.time == 0)
        #expect(abs(cpa.distance - 500) < 0.001)
    }

    @Test("Local frame: one minute of latitude is one nautical mile")
    func localFrame() {
        let frame = LocalFrame(origin: Coordinate(latitude: 60, longitude: 25))
        let north = frame.offset(of: Coordinate(latitude: 60 + 1.0 / 60, longitude: 25))
        let east = frame.offset(of: Coordinate(latitude: 60, longitude: 25 + 1.0 / 60))
        #expect(abs(north.y - 1852) < 0.001)
        #expect(abs(east.x - 926) < 0.01) // cos(60°) = 0.5
    }
}

// The compass card animates between headings. Through north it must turn the short way,
// or the whole card spins round in front of the helmsman.
struct ContinuousAngleTests {
    @Test(arguments: [
        (359.0, 1.0, 361.0),
        (1.0, 359.0, -1.0),
        (720.0, 10.0, 730.0),
        (90.0, 270.0, 270.0),
        (-170.0, 170.0, -190.0),
        (45.0, 45.0, 45.0),
    ])
    func shortestTurn(previous: Double, target: Double, expected: Double) {
        #expect(abs(ContinuousAngle.nearest(to: previous, target: target) - expected) < 1e-9)
    }
}
