import Foundation

/// Converts Signal K SI values into text for display.
public enum Format {
    public enum Side: Sendable, Equatable { case port, starboard }

    /// m/s → knots, one decimal: "6.1".
    public static func knots(_ metresPerSecond: Double) -> String {
        String(format: "%.1f", metresPerSecond * 3600 / 1852)
    }

    /// m/s → the chosen speed unit, one decimal.
    public static func speed(_ metresPerSecond: Double, in unit: DisplayUnit) -> String {
        switch unit {
        case .kilometresPerHour: String(format: "%.1f", metresPerSecond * 3.6)
        case .metresPerSecond: String(format: "%.1f", metresPerSecond)
        default: knots(metresPerSecond)
        }
    }

    /// Metres → the chosen depth unit, one decimal.
    public static func depth(_ metres: Double, in unit: DisplayUnit) -> String {
        switch unit {
        case .feet: String(format: "%.1f", metres / 0.3048)
        case .fathoms: String(format: "%.1f", metres / 1.8288)
        default: self.metres(metres)
        }
    }

    /// Kelvin → the chosen temperature unit, one decimal.
    public static func temperature(_ kelvin: Double, in unit: DisplayUnit) -> String {
        unit == .fahrenheit ? String(format: "%.1f", (kelvin - 273.15) * 9 / 5 + 32) : celsius(kelvin)
    }

    /// Radians → whole degrees 000–359, as on marine instruments: "005", "224".
    public static func bearing(_ radians: Double) -> String {
        // Integer arithmetic: a Double rounded from -0.4 is -0.0 and would print as "-00".
        let degrees = (Int((radians * 180 / .pi).rounded()) % 360 + 360) % 360
        return String(format: "%03d", degrees)
    }

    /// Wind angle in radians (−π…π, negative is port) → whole degrees 0–180 and the side.
    public static func windAngle(_ radians: Double) -> (degrees: String, side: Side) {
        let degrees = (radians * 180 / .pi).rounded()
        return (String(format: "%.0f", min(abs(degrees), 180)), degrees < 0 ? .port : .starboard)
    }

    /// Metres, one decimal: "10.4".
    public static func metres(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Kelvin → °C, one decimal: "18.3".
    public static func celsius(_ kelvin: Double) -> String {
        String(format: "%.1f", kelvin - 273.15)
    }

    /// Volts, two decimals: "12.84".
    public static func volts(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Degrees and decimal minutes: "59°43.501′ N".
    public static func latitude(_ degrees: Double) -> String {
        latitude(degrees, format: .degreesMinutes)
    }

    /// Degrees and decimal minutes: "024°44.201′ E".
    public static func longitude(_ degrees: Double) -> String {
        longitude(degrees, format: .degreesMinutes)
    }

    /// Latitude in a position format: "59°43.501′ N", "59°43′30.1″ N" or "59.72501° N".
    public static func latitude(_ degrees: Double, format: DisplayUnit) -> String {
        coordinate(degrees, format: format, degreeDigits: 2, positive: "N", negative: "S")
    }

    /// Longitude in a position format: "024°44.201′ E", "024°44′12.0″ E" or "24.73668° E".
    public static func longitude(_ degrees: Double, format: DisplayUnit) -> String {
        coordinate(degrees, format: format, degreeDigits: 3, positive: "E", negative: "W")
    }

    private static func coordinate(_ value: Double, format: DisplayUnit, degreeDigits: Int,
                                   positive: String, negative: String) -> String {
        let hemisphere = value < 0 ? negative : positive
        switch format {
        case .decimalDegrees:
            return String(format: "%.5f° %@", abs(value), hemisphere)
        case .degreesMinutesSeconds:
            // Round to 0.1″ first, for the same reason as below (never 60.0″).
            let tenthsOfSecond = (abs(value) * 36_000).rounded()
            let degrees = Int(tenthsOfSecond / 36_000)
            let minutes = Int((tenthsOfSecond - Double(degrees) * 36_000) / 600)
            let seconds = (tenthsOfSecond - Double(degrees) * 36_000 - Double(minutes) * 600) / 10
            return String(format: "%0\(degreeDigits)d°%02d′%04.1f″ %@", degrees, minutes, seconds, hemisphere)
        default:
            return degreesMinutes(value, degreeDigits: degreeDigits, hemisphere: hemisphere)
        }
    }

    private static func degreesMinutes(_ value: Double, degreeDigits: Int, hemisphere: String) -> String {
        // Round to 0.001′ first, so 59.99999° shows as 60°00.000′ and never as 59°60.000′.
        let thousandthsOfMinute = (abs(value) * 60_000).rounded()
        let degrees = Int(thousandthsOfMinute / 60_000)
        let minutes = (thousandthsOfMinute - Double(degrees) * 60_000) / 1000
        return String(format: "%0\(degreeDigits)d°%06.3f′ %@", degrees, minutes, hemisphere)
    }
}
