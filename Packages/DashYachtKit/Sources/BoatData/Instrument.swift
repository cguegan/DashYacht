import Foundation

/// One path from one source, chosen by the user for an instrument.
public struct SourceSelection: Codable, Hashable, Sendable {
    public var path: String
    /// `nil` when the data has no source reference.
    public var sourceRef: String?

    public init(path: String, sourceRef: String?) {
        self.path = path
        self.sourceRef = sourceRef
    }
}

/// Units the user can choose for a card.
public enum DisplayUnit: String, Codable, CaseIterable, Sendable {
    case knots, kilometresPerHour, metresPerSecond
    case metres, feet, fathoms
    case celsius, fahrenheit
    case degreesMinutes, degreesMinutesSeconds, decimalDegrees

    /// Name in the settings menu.
    public var name: String {
        switch self {
        case .knots: "Knots"
        case .kilometresPerHour: "Kilometres per hour"
        case .metresPerSecond: "Metres per second"
        case .metres: "Metres"
        case .feet: "Feet"
        case .fathoms: "Fathoms"
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        case .degreesMinutes: "Degrees, decimal minutes"
        case .degreesMinutesSeconds: "Degrees, minutes, seconds"
        case .decimalDegrees: "Decimal degrees"
        }
    }

    /// Text next to the value. Empty for position formats.
    public var symbol: String {
        switch self {
        case .knots: "kts"
        case .kilometresPerHour: "km/h"
        case .metresPerSecond: "m/s"
        case .metres: "m"
        case .feet: "ft"
        case .fathoms: "fm"
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .degreesMinutes, .degreesMinutesSeconds, .decimalDegrees: ""
        }
    }
}

/// The instruments a card can show.
public enum Instrument: String, Codable, CaseIterable, Sendable {
    case speedOverGround, speedThroughWater, heading, courseOverGround, depth, position
    case apparentWindAngle, apparentWindSpeed, trueWindAngle, trueWindSpeed, waterTemperature, batteryVoltage

    public var title: String {
        switch self {
        case .speedOverGround: "SOG"
        case .speedThroughWater: "STW"
        case .heading: "Heading"
        case .courseOverGround: "COG"
        case .depth: "Depth"
        case .position: "Position"
        case .apparentWindAngle: "AWA"
        case .apparentWindSpeed: "AWS"
        case .trueWindAngle: "TWA"
        case .trueWindSpeed: "TWS"
        case .waterTemperature: "Water"
        case .batteryVoltage: "Battery"
        }
    }

    /// Full name, for the settings menu.
    public var name: String {
        switch self {
        case .speedOverGround: "Speed over ground (SOG)"
        case .speedThroughWater: "Speed through water (STW)"
        case .heading: "Heading"
        case .courseOverGround: "Course over ground (COG)"
        case .depth: "Depth"
        case .position: "Position"
        case .apparentWindAngle: "Apparent wind angle (AWA)"
        case .apparentWindSpeed: "Apparent wind speed (AWS)"
        case .trueWindAngle: "True wind angle (TWA)"
        case .trueWindSpeed: "True wind speed (TWS)"
        case .waterTemperature: "Water temperature"
        case .batteryVoltage: "Battery voltage"
        }
    }

    /// Signal K paths in order of preference. In automatic mode the first live one is used.
    public var paths: [String] {
        switch self {
        case .speedOverGround: ["navigation.speedOverGround"]
        case .speedThroughWater: ["navigation.speedThroughWater"]
        case .heading: ["navigation.headingTrue", "navigation.headingMagnetic"]
        case .courseOverGround: ["navigation.courseOverGroundTrue", "navigation.courseOverGroundMagnetic"]
        case .depth: ["environment.depth.belowKeel", "environment.depth.belowTransducer", "environment.depth.belowSurface"]
        case .position: ["navigation.position"]
        case .apparentWindAngle: ["environment.wind.angleApparent"]
        case .apparentWindSpeed: ["environment.wind.speedApparent"]
        case .trueWindAngle: ["environment.wind.angleTrueWater"]
        case .trueWindSpeed: ["environment.wind.speedTrue"]
        case .waterTemperature: ["environment.water.temperature"]
        case .batteryVoltage: ["electrical.batteries.*.voltage"]
        }
    }

    /// Units the user can choose, default first. Empty when there is no choice.
    public var units: [DisplayUnit] {
        switch self {
        case .speedOverGround, .speedThroughWater, .apparentWindSpeed, .trueWindSpeed:
            [.knots, .kilometresPerHour, .metresPerSecond]
        case .depth: [.metres, .feet, .fathoms]
        case .waterTemperature: [.celsius, .fahrenheit]
        case .position: [.degreesMinutes, .degreesMinutesSeconds, .decimalDegrees]
        case .heading, .courseOverGround, .apparentWindAngle, .trueWindAngle, .batteryVoltage: []
        }
    }

    /// What the card shows for a reading, or `nil` when the value has the wrong type.
    public func value(of reading: Reading, unit: DisplayUnit?) -> InstrumentValue? {
        let unit = unit.flatMap { units.contains($0) ? $0 : nil } ?? units.first
        let path = reading.path
        if self == .position {
            guard let lat = reading.sample.value["latitude"]?.number,
                  let lon = reading.sample.value["longitude"]?.number else { return nil }
            let format = unit ?? .degreesMinutes
            // Signal K positions are WGS84 by specification.
            return InstrumentValue(lines: [Format.latitude(lat, format: format), Format.longitude(lon, format: format)],
                                   unit: "", detail: "WGS84")
        }
        guard let number = reading.sample.value.number else { return nil }
        switch self {
        case .speedOverGround, .speedThroughWater, .apparentWindSpeed, .trueWindSpeed:
            let unit = unit ?? .knots
            return InstrumentValue(lines: [Format.speed(number, in: unit)], unit: unit.symbol)
        case .heading, .courseOverGround:
            return InstrumentValue(lines: [Format.bearing(number) + "°"], unit: path.hasSuffix("Magnetic") ? "M" : "T")
        case .apparentWindAngle, .trueWindAngle:
            let angle = Format.windAngle(number)
            return InstrumentValue(lines: [angle.degrees + "°"], unit: angle.side == .port ? "Port" : "Stbd",
                                   side: angle.side)
        case .depth:
            let unit = unit ?? .metres
            let reference = switch path.split(separator: ".").last {
            case "belowKeel": "Below keel"
            case "belowTransducer": "Below transducer"
            default: "Below surface"
            }
            return InstrumentValue(lines: [Format.depth(number, in: unit)], unit: unit.symbol, detail: reference)
        case .waterTemperature:
            let unit = unit ?? .celsius
            return InstrumentValue(lines: [Format.temperature(number, in: unit)], unit: unit.symbol)
        case .batteryVoltage:
            return InstrumentValue(lines: [Format.volts(number)], unit: "V",
                                   detail: "Battery " + path.split(separator: ".")[2])
        case .position:
            return nil
        }
    }
}

/// Text of a card, ready to draw.
public struct InstrumentValue: Equatable, Sendable {
    /// One line, or two for a position.
    public var lines: [String]
    public var unit: String
    /// Set for wind angles, so the card can colour the side.
    public var side: Format.Side?
    /// Bottom line, for example the depth reference. When `nil` the card shows the source.
    public var detail: String?

    public init(lines: [String], unit: String, side: Format.Side? = nil, detail: String? = nil) {
        self.lines = lines
        self.unit = unit
        self.side = side
        self.detail = detail
    }
}

/// What one card on the dashboard shows. Saved with the dashboard.
public struct CardSettings: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public private(set) var instrument: Instrument
    /// `nil` is automatic: the first live path of the instrument, from any source.
    public var source: SourceSelection?
    /// `nil` is the default unit of the instrument.
    public var unit: DisplayUnit?

    public init(id: UUID = UUID(), instrument: Instrument, source: SourceSelection? = nil, unit: DisplayUnit? = nil) {
        self.id = id
        self.instrument = instrument
        self.source = source
        self.unit = unit
    }

    /// Shows another instrument. The source and unit of the old one do not apply, so they go back to automatic.
    public mutating func change(to instrument: Instrument) {
        guard instrument != self.instrument else { return }
        self.instrument = instrument
        source = nil
        unit = nil
    }
}
