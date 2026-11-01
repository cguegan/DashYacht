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
    /// Phase 1: one fixed page. Editable dashboards come in phase 2.
    static let defaultPage: [InstrumentSpec] = [
        InstrumentSpec(title: "SOG", paths: ["navigation.speedOverGround"]) { reading in
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
        InstrumentSpec(title: "STW", paths: ["navigation.speedThroughWater"]) { reading in
            reading.sample.value.number.map { .init(value: Format.knots($0), unit: "kn") }
        },
        InstrumentSpec(title: "Depth", paths: [
            "environment.depth.belowKeel", "environment.depth.belowTransducer", "environment.depth.belowSurface",
        ]) { reading in
            reading.sample.value.number.map {
                .init(value: Format.metres($0), unit: "m", detail: depthReference(reading.path))
            }
        },
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
        InstrumentSpec(title: "Position", paths: ["navigation.position"]) { reading in
            guard let lat = reading.sample.value["latitude"]?.number,
                  let lon = reading.sample.value["longitude"]?.number else { return nil }
            return .init(value: Format.latitude(lat) + "\n" + Format.longitude(lon), unit: "")
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

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Redraw every second even without new data, so values turn stale on time.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(InstrumentSpec.defaultPage) { spec in
                        InstrumentTile(spec: spec, reading: model.store.reading(spec.paths, now: context.date))
                    }
                }
                .padding(16)
            }
        }
    }
}

struct InstrumentTile: View {
    let spec: InstrumentSpec
    let reading: Reading?

    var body: some View {
        let display = reading.flatMap(spec.display)
        let isLive = reading?.isLive == true && display != nil

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(spec.title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                if let status = statusText {
                    Text(status).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(display?.value ?? "—")
                    .font(.system(size: isMultiline(display) ? 26 : 48, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let display, !display.unit.isEmpty {
                    Text(display.unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isLive ? (display.unitColor ?? .secondary) : .secondary)
                }
            }
            .foregroundStyle(isLive ? .primary : .tertiary)
            Text(display?.detail ?? " ")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var statusText: String? {
        guard let reading else { return "No data" }
        if case .stale(let age) = reading.freshness {
            return age < 120 ? "Old: \(Int(age)) s" : "Old: \(Int(age / 60)) min"
        }
        return nil
    }

    private func isMultiline(_ display: InstrumentSpec.Display?) -> Bool {
        display?.value.contains("\n") == true
    }
}
