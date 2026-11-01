import BoatData
import SignalK
import SwiftUI

/// Heading-up compass: the card turns so the boat heading is always at the top.
struct CompassView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isNightVision) private var isNightVision
    @AppStorage(EngineSettings.maxRPMKey) private var maxRPM = EngineSettings.defaultMaxRPM

    var body: some View {
        // Redraw every second even without new data, so the dial turns stale on time.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let store = model.store
            let heading = store.reading(["navigation.headingTrue", "navigation.headingMagnetic"], now: context.date)
            // Use the same reference as the heading, so true and magnetic are not mixed.
            let apparentWind = store.reading("environment.wind.angleApparent", now: context.date)
            let isMagnetic = heading?.path.hasSuffix("Magnetic") == true
            let cogPaths = isMagnetic
                ? ["navigation.courseOverGroundMagnetic", "navigation.courseOverGroundTrue"]
                : ["navigation.courseOverGroundTrue", "navigation.courseOverGroundMagnetic"]
            CompassDial(
                heading: heading,
                rotation: cardRotation,
                course: store.reading(cogPaths, now: context.date),
                apparentWind: apparentWind,
                windAngle: windAngle
            )
            // Headings arrive a few times per second: turn the card smoothly, the short way round.
            .onChange(of: heading?.sample.value.number, initial: true) { _, radians in
                guard let radians else { return }
                let target = ContinuousAngle.nearest(to: cardRotation, target: radians * 180 / .pi)
                if hasRotation {
                    withAnimation(Self.motion) { cardRotation = target }
                } else {
                    cardRotation = target
                    hasRotation = true
                }
            }
            // Apparent wind changes all the time: the pointer follows smoothly, the short way round
            // (through dead downwind, not round the bow).
            .onChange(of: apparentWind?.sample.value.number, initial: true) { _, radians in
                guard let radians else { return }
                let target = ContinuousAngle.nearest(to: windAngle, target: radians * 180 / .pi)
                if hasWind {
                    withAnimation(Self.motion) { windAngle = target }
                } else {
                    windAngle = target
                    hasWind = true
                }
            }
            .overlay {
                let rudder = store.reading("steering.rudderAngle", now: context.date)
                let degrees = (rudder?.sample.value.number ?? 0) * 180 / .pi
                // The angle asked by the autopilot or steering system. Shown only while it is sent:
                // in standby the autopilot stops sending, and an old request would mislead.
                let request = store.reading("steering.rudderAngleTarget", now: context.date)
                let requestNumber = request?.isLive == true ? request?.sample.value.number : nil
                BandGauge(
                    placement: .bottom,
                    value: degrees,
                    hasValue: rudder?.sample.value.number != nil,
                    isLive: rudder?.isLive == true,
                    // Most rudders stop near 35°.
                    scale: 35,
                    label: rudder == nil ? "RUDDER ---" : Self.sideLabel("RUDDER", degrees, unit: "°"),
                    // Bar: actual rudder angle. Triangle: requested angle.
                    pointer: requestNumber == nil ? .hidden : .atTarget,
                    target: (requestNumber ?? 0) * 180 / .pi
                )
                // Values arrive a few times per second: animate between them so the bar moves smoothly.
                .animation(.linear(duration: 0.2), value: rudder?.sample.value.number)
                .animation(.linear(duration: 0.2), value: requestNumber)
            }
            .overlay {
                let rateOfTurn = store.reading("navigation.rateOfTurn", now: context.date)
                // Signal K gives rad/s; helmsmen read degrees per minute.
                let degreesPerMinute = (rateOfTurn?.sample.value.number ?? 0) * 180 / .pi * 60
                BandGauge(
                    placement: .top,
                    value: degreesPerMinute,
                    hasValue: rateOfTurn?.sample.value.number != nil,
                    isLive: rateOfTurn?.isLive == true,
                    // Yaw in waves reaches about 60°/min; faster turns stop at the end of the band.
                    scale: 60,
                    label: rateOfTurn == nil ? "ROT ---" : Self.sideLabel("ROT", degreesPerMinute, unit: "°/MIN"),
                    // Nothing requests a rate of turn, so no triangle.
                    pointer: .hidden
                )
                // Same 1 s spring as the compass card, so the band moves with the heading.
                .animation(Self.motion, value: rateOfTurn?.sample.value.number)
            }
            .overlay {
                // Wider than the dial, so the RPM text fits beside each band. Same height and centre,
                // so the dial geometry is the same.
                GeometryReader { geometry in
                    ZStack {
                        engineGauge("port", placement: .left, now: context.date)
                        engineGauge("starboard", placement: .right, now: context.date)
                    }
                    .frame(width: geometry.size.width * 1.5, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            .overlay {
                let scene = AISScene(store: store, now: context.date, rangeMetres: rangeNM * 1852)
                // The card may turn with a magnetic heading; AIS needs true. Add the difference (the variation),
                // so targets turn with the card, in the same animation.
                let offset = heading?.sample.value.number.map {
                    ContinuousAngle.nearest(to: 0, target: (scene.trueHeading - $0) * 180 / .pi)
                } ?? 0
                AISLayer(scene: scene, rotation: cardRotation + offset)
            }
            .padding(24)
        }
        // The window has no title bar, so the connection status is here. A click opens the data source.
        .overlay(alignment: .topLeading) {
            if let source = model.source {
                Button { model.showsSourceSheet = true } label: {
                    StatusView(source: source, status: model.status)
                }
                .buttonStyle(.plain)
                .padding(12)
                .help("Data Source (⌘O)")
            }
        }
        .overlay(alignment: .bottomLeading) {
            Picker("Range", selection: $rangeNM) {
                ForEach(Self.ranges, id: \.self) { range in
                    Text("\(range.formatted()) NM").tag(range)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .font(.system(.caption, design: .monospaced))
            .padding(12)
            .help("AIS range: radius of the outer ring")
        }
    }

    @AppStorage("ais.rangeNM") private var rangeNM = 4.0
    /// Card rotation in degrees. Not limited to 0–360°, so the animation never turns the long way.
    @State private var cardRotation = 0.0
    @State private var hasRotation = false
    /// Apparent wind angle in degrees, continuous like `cardRotation`.
    @State private var windAngle = 0.0
    @State private var hasWind = false

    /// Spring without bounce for the card and the wind pointer: it keeps its speed when a new value
    /// arrives (no pulsing in a steady turn) and never overshoots, which would show a wrong value.
    /// Longer is smoother but shows changes later.
    private static let motion = Animation.smooth(duration: 1.0)

    /// RPM band of one engine, from Signal K `propulsion.<id>`. Ahead up, astern down.
    /// Bar: actual RPM. Triangle: RPM requested by the engine control lever.
    private func engineGauge(_ id: String, placement: BandGauge.Placement, now: Date) -> some View {
        let store = model.store
        let revolutions = store.reading("propulsion.\(id).revolutions", now: now)
        let gear = store.reading("propulsion.\(id).transmission.gear", now: now)
        // Lever position as requested revolutions, Hz, negative astern. Not a standard Signal K path:
        // the specification has no engine control lever. Shown only while it is sent.
        let request = store.reading("propulsion.\(id).revolutionsTarget", now: now)
        let requestHertz = request?.isLive == true ? request?.sample.value.number : nil
        let engine = EngineState(revolutions: revolutions?.sample.value, gear: gear?.sample.value)
        let palette = HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision)
        return BandGauge(
            placement: placement,
            value: engine?.signedRPM ?? 0,
            hasValue: engine != nil,
            isLive: revolutions?.isLive == true,
            scale: maxRPM,
            label: engine?.text ?? "---",
            // Astern in orange, so it is never mistaken for ahead.
            colors: (negative: isNightVision ? palette.accent : .orange, positive: palette.accent),
            pointer: requestHertz == nil ? .hidden : .atTarget,
            target: (requestHertz ?? 0) * 60
        )
        .animation(Self.motion, value: engine?.signedRPM)
        .animation(Self.motion, value: requestHertz)
    }

    /// "RUDDER 21° S", "ROT 04°/MIN P", or "RUDDER 00°  " at zero. Always the same length (the font is
    /// monospaced), so the centred text does not jump when the value changes.
    private static func sideLabel(_ name: String, _ value: Double, unit: String) -> String {
        let rounded = Int(abs(value).rounded())
        let side = rounded == 0 ? " " : value < 0 ? "P" : "S"
        return "\(name) \(String(format: "%02d", rounded))\(unit) \(side)"
    }
    private static let ranges: [Double] = [0.5, 1, 2, 4, 8, 16, 32]
}

struct CompassDial: View, Animatable {
    let heading: Reading?
    /// Degrees, animated. Follows the heading, the short way round.
    var rotation: Double
    let course: Reading?
    let apparentWind: Reading?
    /// Degrees from the bow, animated. Follows the apparent wind, the short way round.
    var windAngle: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rotation, windAngle) }
        set {
            rotation = newValue.first
            windAngle = newValue.second
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isNightVision) private var isNightVision

    var body: some View {
        let palette = HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision)
        Canvas { context, size in
            let dial = DialGeometry(size: size)
            let headingDegrees = heading == nil ? 0 : rotation
            let headingLive = heading?.isLive == true

            drawFrame(context, dial, palette)

            // Compass card. Dim when the heading is old or missing, because its orientation is wrong.
            var card = context
            card.opacity = headingLive ? 1 : 0.3
            drawCard(card, dial, rotation: headingDegrees)

            if let courseDegrees = degrees(course) {
                var layer = context
                layer.opacity = course?.isLive == true && headingLive ? 1 : 0.3
                drawCourse(layer, dial, angle: courseDegrees - headingDegrees, color: palette.course)
            }
            if apparentWind?.sample.value.number != nil {
                var layer = context
                layer.opacity = apparentWind?.isLive == true ? 1 : 0.3
                drawWind(layer, dial, angle: windAngle, color: palette.wind)
            }

            drawBoat(context, dial)
            drawHeadingBox(context, dial, palette)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private func degrees(_ reading: Reading?) -> Double? {
        reading?.sample.value.number.map { $0 * 180 / .pi }
    }

    // MARK: - Drawing

    /// Fixed decoration around the dial.
    private func drawFrame(_ context: GraphicsContext, _ dial: DialGeometry, _ palette: HUDPalette) {
        let r = dial.radius

        // Inner dashed circle and dotted cross line, as on an aircraft navigation display.
        context.stroke(Path(ellipseIn: CGRect(x: dial.center.x - r / 2, y: dial.center.y - r / 2, width: r, height: r)),
                       with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        var cross = Path()
        cross.move(to: dial.point(270, r * 0.97))
        cross.addLine(to: dial.point(90, r * 0.97))
        context.stroke(cross, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
    }

    /// Ring, ticks and labels, turned so that `rotation` is at the top.
    private func drawCard(_ context: GraphicsContext, _ dial: DialGeometry, rotation: Double) {
        let r = dial.radius
        context.stroke(Path(ellipseIn: CGRect(x: dial.center.x - r, y: dial.center.y - r, width: r * 2, height: r * 2)),
                       with: .color(.primary), lineWidth: 2)

        var minor = Path()
        var major = Path()
        for bearing in stride(from: 0, to: 360, by: 5) {
            let angle = Double(bearing) - rotation
            let length: CGFloat = bearing % 30 == 0 ? 0.09 : bearing % 10 == 0 ? 0.06 : 0.035
            var path = bearing % 30 == 0 ? major : minor
            path.move(to: dial.point(angle, r))
            path.addLine(to: dial.point(angle, r * (1 - length)))
            if bearing % 30 == 0 { major = path } else { minor = path }
        }
        context.stroke(minor, with: .color(.primary.opacity(0.7)), lineWidth: 1)
        context.stroke(major, with: .color(.primary), lineWidth: 2)

        let labels = ["N", "030", "060", "E", "120", "150", "S", "210", "240", "W", "300", "330"]
        for (index, label) in labels.enumerated() {
            let angle = Double(index * 30) - rotation
            let isCardinal = index % 3 == 0
            let text = context.resolve(
                Text(label)
                    .font(.system(size: r * (isCardinal ? 0.11 : 0.08), weight: isCardinal ? .semibold : .regular,
                                  design: .monospaced))
                    .foregroundStyle(.primary)
            )
            var layer = context
            let position = dial.point(angle, r * 0.8)
            layer.translateBy(x: position.x, y: position.y)
            layer.rotate(by: .degrees(angle))
            layer.draw(text, at: .zero)
        }
    }

    /// Dashed course line from the boat, with a diamond on the ring.
    private func drawCourse(_ context: GraphicsContext, _ dial: DialGeometry, angle: Double, color: Color) {
        let r = dial.radius
        var line = Path()
        line.move(to: dial.center)
        line.addLine(to: dial.point(angle, r * 0.93))
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))

        let tip = dial.point(angle, r)
        let s = r * 0.035
        var diamond = Path()
        diamond.move(to: CGPoint(x: tip.x, y: tip.y - s))
        diamond.addLine(to: CGPoint(x: tip.x + s, y: tip.y))
        diamond.addLine(to: CGPoint(x: tip.x, y: tip.y + s))
        diamond.addLine(to: CGPoint(x: tip.x - s, y: tip.y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(color))
    }

    /// Apparent wind: triangle outside the ring pointing at the boat. The angle is relative to the bow.
    private func drawWind(_ context: GraphicsContext, _ dial: DialGeometry, angle: Double, color: Color) {
        let r = dial.radius
        var triangle = Path()
        triangle.move(to: dial.point(angle, r * 1.02))
        triangle.addLine(to: dial.point(angle - 4, r * 1.1))
        triangle.addLine(to: dial.point(angle + 4, r * 1.1))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(color))

        var line = Path()
        line.move(to: dial.point(angle, r * 0.97))
        line.addLine(to: dial.point(angle, r * 0.62))
        context.stroke(line, with: .color(color), lineWidth: 2)
    }

    /// Boat outline in the centre, bow up.
    private func drawBoat(_ context: GraphicsContext, _ dial: DialGeometry) {
        let length = dial.radius * 0.2
        let beam = length * 0.38
        let c = dial.center
        var hull = Path()
        hull.move(to: CGPoint(x: c.x, y: c.y - length / 2))
        hull.addQuadCurve(to: CGPoint(x: c.x + beam / 2, y: c.y + length * 0.15),
                          control: CGPoint(x: c.x + beam / 2, y: c.y - length * 0.3))
        hull.addLine(to: CGPoint(x: c.x + beam * 0.4, y: c.y + length / 2))
        hull.addLine(to: CGPoint(x: c.x - beam * 0.4, y: c.y + length / 2))
        hull.addLine(to: CGPoint(x: c.x - beam / 2, y: c.y + length * 0.15))
        hull.addQuadCurve(to: CGPoint(x: c.x, y: c.y - length / 2),
                          control: CGPoint(x: c.x - beam / 2, y: c.y - length * 0.3))
        context.stroke(hull, with: .color(.primary), lineWidth: 1.5)
    }

    /// Fixed lubber line and heading value at the top.
    private func drawHeadingBox(_ context: GraphicsContext, _ dial: DialGeometry, _ palette: HUDPalette) {
        let r = dial.radius
        let accent = GraphicsContext.Shading.color(palette.accent)

        var lubber = Path()
        let top = dial.point(0, r)
        lubber.move(to: CGPoint(x: top.x, y: top.y + 2))
        lubber.addLine(to: CGPoint(x: top.x - r * 0.04, y: top.y - r * 0.07))
        lubber.addLine(to: CGPoint(x: top.x + r * 0.04, y: top.y - r * 0.07))
        lubber.closeSubpath()
        context.fill(lubber, with: accent)

        let box = dial.headingBox
        // Filled, so the course line and wind pointer under it do not cross the digits.
        let fill: GraphicsContext.Shading = isNightVision ? .color(.black)
            : palette.background.map { .color($0) } ?? .style(.background)
        context.fill(Path(box), with: fill)
        context.stroke(Path(box), with: accent, lineWidth: 1.5)

        let value: String
        if let heading, let number = heading.sample.value.number {
            value = Format.bearing(number) + "°" + (heading.path.hasSuffix("Magnetic") ? "M" : "T")
        } else {
            value = "---"
        }
        let text = context.resolve(
            Text(value)
                .font(.system(size: r * 0.11, weight: .medium, design: .monospaced))
                .foregroundStyle(heading?.isLive == true ? .primary : .secondary)
        )
        context.draw(text, at: CGPoint(x: box.midX, y: box.midY))

        let label = context.resolve(
            Text(heading == nil ? "NO DATA" : heading?.isLive == true ? "HDG" : "HDG  OLD")
                .font(.system(size: r * 0.05, weight: .semibold, design: .monospaced))
                .foregroundStyle(heading?.isLive == true ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
        )
        let labelSize = label.measure(in: CGSize(width: r, height: r))
        let labelRect = CGRect(x: box.midX - labelSize.width / 2 - 3, y: box.maxY + r * 0.02,
                               width: labelSize.width + 6, height: labelSize.height)
        context.fill(Path(labelRect), with: fill)
        context.draw(label, in: labelRect.insetBy(dx: 3, dy: 0))
    }

    private var accessibilityText: String {
        guard let heading, let number = heading.sample.value.number else { return "Compass, no heading data" }
        return "Heading \(Format.bearing(number)) degrees" + (heading.isLive ? "" : ", old data")
    }
}

/// Layout shared by the dial and the AIS layer, so both draw at the same scale.
/// Angles are compass angles: 0° at the top, clockwise.
struct DialGeometry {
    let center: CGPoint
    let radius: CGFloat

    init(size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2 + min(size.width, size.height) * 0.03)
        radius = min(size.width, size.height) / 2 * 0.70
    }

    /// Heading value box, in the centre of the dial just below the boat.
    var headingBox: CGRect {
        CGRect(x: center.x - radius * 0.24, y: center.y + radius * 0.14, width: radius * 0.48, height: radius * 0.17)
    }

    func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(sin(radians)), y: center.y - r * CGFloat(cos(radians)))
    }

    func arc(from start: Double, to end: Double, radius r: CGFloat) -> Path {
        Path { path in
            path.move(to: point(start, r))
            for angle in stride(from: start, through: end, by: 1) {
                path.addLine(to: point(angle, r))
            }
        }
    }
}
