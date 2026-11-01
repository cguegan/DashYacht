import Testing
import BoatData

struct FormatTests {
    @Test("Speed in knots")
    func knots() {
        #expect(Format.knots(1) == "1.9")
        #expect(Format.knots(3.0866) == "6.0")
    }

    @Test("Bearings stay in 000–359 after rounding", arguments: [
        (0.0, "000"), (359.6, "000"), (-0.4, "000"), (-10.0, "350"), (224.44, "224"), (5.0, "005"),
    ])
    func bearing(degrees: Double, expected: String) {
        #expect(Format.bearing(degrees * .pi / 180) == expected)
    }

    @Test("Wind angle shows the side, not a negative number")
    func windAngle() {
        #expect(Format.windAngle(-0.5) == ("29", .port))
        #expect(Format.windAngle(0.5) == ("29", .starboard))
        #expect(Format.windAngle(.pi) == ("180", .starboard))
    }

    @Test("Positions use degrees and decimal minutes, and never show 60 minutes")
    func coordinates() {
        #expect(Format.latitude(59.7250108) == "59°43.501′ N")
        #expect(Format.longitude(-4.5) == "004°30.000′ W")
        #expect(Format.latitude(-33.9999999) == "34°00.000′ S")
    }

    @Test("Temperature from kelvin")
    func celsius() {
        #expect(Format.celsius(291.45) == "18.3")
    }
}
