import Foundation

/// Converts Signal K SI values into text for display.
public enum Format {
    public enum Side: Sendable, Equatable { case port, starboard }

    /// m/s → knots, one decimal: "6.1".
    public static func knots(_ metresPerSecond: Double) -> String {
        String(format: "%.1f", metresPerSecond * 3600 / 1852)
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
        coordinate(degrees, degreeDigits: 2, positive: "N", negative: "S")
    }

    /// Degrees and decimal minutes: "024°44.201′ E".
    public static func longitude(_ degrees: Double) -> String {
        coordinate(degrees, degreeDigits: 3, positive: "E", negative: "W")
    }

    private static func coordinate(_ value: Double, degreeDigits: Int, positive: String, negative: String) -> String {
        // Round to 0.001′ first, so 59.99999° shows as 60°00.000′ and never as 59°60.000′.
        let thousandthsOfMinute = (abs(value) * 60_000).rounded()
        let degrees = Int(thousandthsOfMinute / 60_000)
        let minutes = (thousandthsOfMinute - Double(degrees) * 60_000) / 1000
        let hemisphere = value < 0 ? negative : positive
        return String(format: "%0\(degreeDigits)d°%06.3f′ %@", degrees, minutes, hemisphere)
    }
}
