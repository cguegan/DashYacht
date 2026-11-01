import BoatData
import SignalK
import SwiftUI

/// Heading-up compass: the card turns so the boat heading is always at the top.
struct CompassView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Redraw every second even without new data, so the dial turns stale on time.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let store = model.store
            let heading = store.reading(["navigation.headingTrue", "navigation.headingMagnetic"], now: context.date)
            // Use the same reference as the heading, so true and magnetic are not mixed.
            let isMagnetic = heading?.path.hasSuffix("Magnetic") == true
            let cogPaths = isMagnetic
                ? ["navigation.courseOverGroundMagnetic", "navigation.courseOverGroundTrue"]
                : ["navigation.courseOverGroundTrue", "navigation.courseOverGroundMagnetic"]
            CompassDial(
                heading: heading,
                rotation: cardRotation,
                course: store.reading(cogPaths, now: context.date),
                apparentWind: store.reading("environment.wind.angleApparent", now: context.date)
            )
            // Headings arrive a few times per second: turn the card smoothly, the short way round.
            .onChange(of: heading?.sample.value.number, initial: true) { _, radians in
                guard let radians else { return }
                let target = ContinuousAngle.nearest(to: cardRotation, target: radians * 180 / .pi)
                if hasRotation {
                    withAnimation(.linear(duration: 0.25)) { cardRotation = target }
                } else {
                    cardRotation = target
                    hasRotation = true
                }
            }
            .overlay {
                let rudder = store.reading("steering.rudderAngle", now: context.date)
                RudderIndicator(
                    angle: (rudder?.sample.value.number ?? 0) * 180 / .pi,
                    hasValue: rudder?.sample.value.number != nil,
                    isLive: rudder?.isLive == true
                )
                // Values arrive a few times per second: animate between them so the bar moves smoothly.
                .animation(.linear(duration: 0.2), value: rudder?.sample.value.number)
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
    private static let ranges: [Double] = [0.5, 1, 2, 4, 8, 16, 32]
}

struct CompassDial: View, Animatable {
    let heading: Reading?
    /// Degrees, animated. Follows the heading, the short way round.
    var rotation: Double
    let course: Reading?
    let apparentWind: Reading?

    nonisolated var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
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
            if let windDegrees = degrees(apparentWind) {
                var layer = context
                layer.opacity = apparentWind?.isLive == true ? 1 : 0.3
                drawWind(layer, dial, angle: windDegrees, color: palette.wind)
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
        let accent = GraphicsContext.Shading.color(palette.accent)

        // Thick brackets on both sides.
        for (start, end) in [(55.0, 125.0), (235.0, 305.0)] {
            context.stroke(dial.arc(from: start, to: end, radius: r * 1.12), with: accent,
                           style: StrokeStyle(lineWidth: 4, lineCap: .butt))
            context.stroke(dial.arc(from: start - 12, to: end + 12, radius: r * 1.18), with: .color(.secondary),
                           lineWidth: 0.75)
        }
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

        let labels = ["N", "3", "6", "E", "12", "15", "S", "21", "24", "W", "30", "33"]
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

        let box = CGRect(x: top.x - r * 0.24, y: top.y - r * 0.27, width: r * 0.48, height: r * 0.17)
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
        context.draw(label, at: CGPoint(x: box.minX - r * 0.04, y: box.midY), anchor: .trailing)
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
