import BoatData
import SignalK
import SwiftUI

/// One instrument on the dashboard: which paths to read and how to show the value.
struct InstrumentSpec: Identifiable, Sendable {
    struct Display: Sendable {
        var value: String
        var unit: String
        var unitColor: Color? = nil
        var detail: String? = nil
    }

    let title: String
    /// Alternatives in order of preference. The first live one is used.
    let paths: [String]
    let display: @Sendable (Reading) -> Display?
    var id: String { title }
}

extension InstrumentSpec {
    /// Fixed for now. Editable dashboards come in phase 2.
    static let leftPanel: [InstrumentSpec] = [
        InstrumentSpec(title: "SOG", paths: ["navigation.speedOverGround"]) { reading in
            reading.sample.value.number.map { .init(value: Format.knots($0), unit: "kn") }
        },
        InstrumentSpec(title: "STW", paths: ["navigation.speedThroughWater"]) { reading in
            reading.sample.value.number.map { .init(value: Format.knots($0), unit: "kn") }
        },
        InstrumentSpec(title: "COG", paths: ["navigation.courseOverGroundTrue", "navigation.courseOverGroundMagnetic"]) { reading in
            reading.sample.value.number.map {
                .init(value: Format.bearing($0) + "°", unit: reading.path.hasSuffix("Magnetic") ? "M" : "T")
            }
        },
        InstrumentSpec(title: "Heading", paths: ["navigation.headingTrue", "navigation.headingMagnetic"]) { reading in
            reading.sample.value.number.map {
                .init(value: Format.bearing($0) + "°", unit: reading.path.hasSuffix("Magnetic") ? "M" : "T")
            }
        },
        InstrumentSpec(title: "Depth", paths: [
            "environment.depth.belowKeel", "environment.depth.belowTransducer", "environment.depth.belowSurface",
        ]) { reading in
            reading.sample.value.number.map {
                .init(value: Format.metres($0), unit: "m", detail: depthReference(reading.path))
            }
        },
        InstrumentSpec(title: "Position", paths: ["navigation.position"]) { reading in
            guard let lat = reading.sample.value["latitude"]?.number,
                  let lon = reading.sample.value["longitude"]?.number else { return nil }
            return .init(value: Format.latitude(lat) + "\n" + Format.longitude(lon), unit: "")
        },
    ]

    static let rightPanel: [InstrumentSpec] = [
        InstrumentSpec(title: "AWA", paths: ["environment.wind.angleApparent"]) { reading in
            reading.sample.value.number.map(windAngle)
        },
        InstrumentSpec(title: "AWS", paths: ["environment.wind.speedApparent"]) { reading in
            reading.sample.value.number.map { .init(value: Format.knots($0), unit: "kn") }
        },
        InstrumentSpec(title: "TWA", paths: ["environment.wind.angleTrueWater"]) { reading in
            reading.sample.value.number.map(windAngle)
        },
        InstrumentSpec(title: "TWS", paths: ["environment.wind.speedTrue"]) { reading in
            reading.sample.value.number.map { .init(value: Format.knots($0), unit: "kn") }
        },
        InstrumentSpec(title: "Water", paths: ["environment.water.temperature"]) { reading in
            reading.sample.value.number.map { .init(value: Format.celsius($0), unit: "°C") }
        },
        InstrumentSpec(title: "Battery", paths: ["electrical.batteries.*.voltage"]) { reading in
            reading.sample.value.number.map {
                .init(value: Format.volts($0), unit: "V", detail: "Battery " + reading.path.split(separator: ".")[2])
            }
        },
    ]

    private static func windAngle(_ radians: Double) -> Display {
        let angle = Format.windAngle(radians)
        return angle.side == .port
            ? .init(value: angle.degrees + "°", unit: "Port", unitColor: .red)
            : .init(value: angle.degrees + "°", unit: "Stbd", unitColor: .green)
    }

    private static func depthReference(_ path: String) -> String {
        switch path.split(separator: ".").last {
        case "belowKeel": "Below keel"
        case "belowTransducer": "Below transducer"
        default: "Below surface"
        }
    }
}

/// Three columns: instrument cards on each side, compass in the centre.
struct DashboardView: View {
    var body: some View {
        // Fixed proportions: 16% cards, 68% compass, 16% cards.
        GeometryReader { geometry in
            let side = geometry.size.width * 0.16
            HStack(spacing: 0) {
                InstrumentColumn(specs: InstrumentSpec.leftPanel)
                    .frame(width: side)
                CompassView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                InstrumentColumn(specs: InstrumentSpec.rightPanel)
                    .frame(width: side)
            }
        }
        .background(GridBackground())
    }
}

struct InstrumentColumn: View {
    @Environment(AppModel.self) private var model
    let specs: [InstrumentSpec]

    var body: some View {
        // Redraw every second even without new data, so values turn stale on time.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(specs) { spec in
                        InstrumentTile(spec: spec, reading: model.store.reading(spec.paths, now: context.date))
                    }
                }
                .padding(12)
            }
        }
    }
}

struct InstrumentTile: View {
    let spec: InstrumentSpec
    let reading: Reading?
    @Environment(\.isNightVision) private var isNightVision
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let display = reading.flatMap(spec.display)
        let isLive = reading?.isLive == true && display != nil
        let palette = HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(spec.title.uppercased())
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let status = statusText {
                    Text(status)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.trailing, 10)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(display?.value ?? "—")
                    .font(.system(size: isMultiline(display) ? 24 : 46, weight: .light))
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let display, !display.unit.isEmpty {
                    Text(display.unit.uppercased())
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                        .foregroundStyle(isLive && !isNightVision ? (display.unitColor ?? .secondary) : .secondary)
                }
            }
            .foregroundStyle(isLive ? .primary : .tertiary)
            Text((display?.detail ?? " ").uppercased())
                .font(.system(.caption2, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background {
            ChamferedRectangle()
                .fill(.background.secondary.opacity(0.7))
            ChamferedRectangle()
                .stroke(.secondary.opacity(0.6), lineWidth: 1)
            CornerMark()
                .fill(isLive ? palette.accent : .orange)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String? {
        guard let reading else { return "NO DATA" }
        if case .stale(let age) = reading.freshness {
            return age < 120 ? "OLD \(Int(age))S" : "OLD \(Int(age / 60))MIN"
        }
        return nil
    }

    private func isMultiline(_ display: InstrumentSpec.Display?) -> Bool {
        display?.value.contains("\n") == true
    }
}
