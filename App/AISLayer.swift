import BoatData
import SwiftUI

/// What the AIS layer needs, in a local frame centred on the own boat.
struct AISScene {
    struct Target: Identifiable {
        var target: AISTarget
        var motion: Motion
        var id: String { target.id }
    }

    /// Why targets cannot be drawn, or `nil` when they can.
    var unavailableReason: String?
    var targets: [Target] = []
    /// Own motion over ground, `nil` when SOG or COG is missing or old (no CPA then).
    var ownMotion: Motion?
    /// Radians, true. Screen up is the bow.
    var trueHeading: Double = 0
    var rangeMetres: Double

    @MainActor
    init(store: DataStore, now: Date, rangeMetres: Double) {
        self.rangeMetres = rangeMetres

        // Positions are relative to the own position: an old own position puts every target in the wrong place.
        guard let own = store.reading("navigation.position", now: now), own.isLive,
              let latitude = own.sample.value["latitude"]?.number,
              let longitude = own.sample.value["longitude"]?.number else {
            unavailableReason = "AIS: NO OWN POSITION"
            return
        }
        // AIS positions give true bearings, so the true heading is needed to place them around the bow.
        if let heading = store.reading("navigation.headingTrue", now: now), heading.isLive,
           let value = heading.sample.value.number {
            trueHeading = value
        } else if let heading = store.reading("navigation.headingMagnetic", now: now), heading.isLive,
                  let variation = store.reading("navigation.magneticVariation", now: now),
                  let value = heading.sample.value.number, let offset = variation.sample.value.number {
            trueHeading = value + offset
        } else {
            unavailableReason = "AIS: NO TRUE HEADING"
            return
        }

        let frame = LocalFrame(origin: Coordinate(latitude: latitude, longitude: longitude))
        if let speed = store.reading("navigation.speedOverGround", now: now), speed.isLive,
           let course = store.reading("navigation.courseOverGroundTrue", now: now), course.isLive,
           let sog = speed.sample.value.number, let cog = course.sample.value.number {
            ownMotion = Motion(position: .zero, speed: sog, course: cog)
        }
        targets = store.aisTargets(now: now).map { target in
            Target(target: target, motion: Motion(position: frame.offset(of: target.position),
                                                  speed: target.speed ?? 0, course: target.course ?? 0))
        }
    }
}

/// AIS targets on the compass, in green. Hover a target to see its closest point of approach.
struct AISLayer: View, Animatable {
    let scene: AISScene
    /// True heading in degrees, animated with the compass card. Screen up is the bow.
    var rotation: Double

    nonisolated var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    @State private var hoveredID: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isNightVision) private var isNightVision

    /// Speed under which a target is drawn as stationary (circle, no course vector): 0.5 kn.
    private static let stationarySpeed = 0.26
    /// Length of the course vector: where the target will be in 6 minutes.
    private static let vectorTime: TimeInterval = 360

    var body: some View {
        let palette = HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision)
        GeometryReader { geometry in
            let dial = DialGeometry(size: geometry.size)
            Canvas { context, canvasSize in
                if let reason = scene.unavailableReason {
                    let text = context.resolve(
                        Text(reason).font(.system(size: dial.radius * 0.045, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                    )
                    context.draw(text, at: dial.point(225, dial.radius * 0.75))
                    return
                }
                drawRangeLabel(context, dial)
                for item in visibleTargets(dial) {
                    var layer = context
                    layer.opacity = item.target.age > DataStore.aisStaleAge ? 0.4 : 1
                    drawTarget(layer, dial, item, color: palette.ais)
                }
                if let hovered = scene.targets.first(where: { $0.id == hoveredID }) {
                    drawClosestApproach(context, dial, hovered, palette, bounds: CGRect(origin: .zero, size: canvasSize))
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredID = visibleTargets(dial)
                        .map { ($0.id, hypot(screenPoint($0.motion.position, dial).x - location.x,
                                             screenPoint($0.motion.position, dial).y - location.y)) }
                        .filter { $0.1 < 14 }
                        .min { $0.1 < $1.1 }?.0
                case .ended:
                    hoveredID = nil
                }
            }
        }
    }

    // MARK: - Projection

    /// Screen point of a position in the local frame (metres east and north of the own boat).
    private func screenPoint(_ offset: SIMD2<Double>, _ dial: DialGeometry) -> CGPoint {
        let bearing = atan2(offset.x, offset.y)
        let distance = (offset * offset).sum().squareRoot()
        let angle = bearing * 180 / .pi - rotation
        return dial.point(angle, dial.radius * CGFloat(distance / scene.rangeMetres))
    }

    /// Targets inside the outer ring (the range).
    private func visibleTargets(_ dial: DialGeometry) -> [AISScene.Target] {
        scene.targets.filter { ($0.motion.position * $0.motion.position).sum().squareRoot() <= scene.rangeMetres }
    }

    // MARK: - Drawing

    private func drawRangeLabel(_ context: GraphicsContext, _ dial: DialGeometry) {
        let half = scene.rangeMetres / 2 / 1852
        let text = context.resolve(
            Text("\(half.formatted()) NM")
                .font(.system(size: dial.radius * 0.04, design: .monospaced))
                .foregroundStyle(.secondary)
        )
        context.draw(text, at: dial.point(135, dial.radius * 0.5 + dial.radius * 0.05))
    }

    /// Triangle pointing along the course, or a circle when the target does not move.
    private func drawTarget(_ context: GraphicsContext, _ dial: DialGeometry, _ item: AISScene.Target, color: Color) {
        let center = screenPoint(item.motion.position, dial)
        let size = dial.radius * 0.03
        let moving = item.target.course != nil && item.motion.speed >= Self.stationarySpeed

        guard moving else {
            context.stroke(Path(ellipseIn: CGRect(x: center.x - size * 0.7, y: center.y - size * 0.7,
                                                  width: size * 1.4, height: size * 1.4)),
                           with: .color(color), lineWidth: 1.5)
            return
        }
        let angle = item.motion.course - rotation * .pi / 180
        func corner(_ a: Double, _ length: CGFloat) -> CGPoint {
            CGPoint(x: center.x + length * CGFloat(sin(angle + a)), y: center.y - length * CGFloat(cos(angle + a)))
        }
        var triangle = Path()
        triangle.move(to: corner(0, size * 1.4))
        triangle.addLine(to: corner(.pi * 0.8, size))
        triangle.addLine(to: corner(-.pi * 0.8, size))
        triangle.closeSubpath()
        context.stroke(triangle, with: .color(color), lineWidth: 1.5)

        var vector = Path()
        vector.move(to: corner(0, size * 1.4))
        vector.addLine(to: screenPoint(item.motion.position + item.motion.velocity * Self.vectorTime, dial))
        context.stroke(vector, with: .color(color), lineWidth: 1)
    }

    /// Both tracks up to the closest point, the gap between the vessels at that time, and the values.
    private func drawClosestApproach(_ context: GraphicsContext, _ dial: DialGeometry, _ item: AISScene.Target,
                                     _ palette: HUDPalette, bounds: CGRect) {
        let targetPoint = screenPoint(item.motion.position, dial)
        let size = dial.radius * 0.055
        context.stroke(Path(ellipseIn: CGRect(x: targetPoint.x - size, y: targetPoint.y - size,
                                              width: size * 2, height: size * 2)),
                       with: .color(palette.ais), lineWidth: 1)

        var lines = [item.target.name ?? item.target.mmsi.map { "MMSI \($0)" } ?? "UNKNOWN"]
        let distance = (item.motion.position * item.motion.position).sum().squareRoot()
        let bearing = atan2(item.motion.position.x, item.motion.position.y)
        lines.append("RNG \(nauticalMiles(distance))  BRG \(Format.bearing(bearing))°")
        if let speed = item.target.speed, let course = item.target.course {
            lines.append("SOG \(Format.knots(speed)) KN  COG \(Format.bearing(course))°")
        }

        if let own = scene.ownMotion, item.target.speed != nil, item.target.course != nil {
            let cpa = ClosestApproach(own: own, target: item.motion)
            let ownAtCPA = screenPoint(cpa.ownPosition, dial)
            let targetAtCPA = screenPoint(cpa.targetPosition, dial)
            let dashed = StrokeStyle(lineWidth: 1.5, dash: [5, 4])

            var ownTrack = Path()
            ownTrack.move(to: dial.center)
            ownTrack.addLine(to: ownAtCPA)
            context.stroke(ownTrack, with: .color(palette.accent), style: dashed)

            var targetTrack = Path()
            targetTrack.move(to: targetPoint)
            targetTrack.addLine(to: targetAtCPA)
            context.stroke(targetTrack, with: .color(palette.ais), style: dashed)

            var gap = Path()
            gap.move(to: ownAtCPA)
            gap.addLine(to: targetAtCPA)
            context.stroke(gap, with: .color(.orange), lineWidth: 2)
            for point in [ownAtCPA, targetAtCPA] {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                             with: .color(.orange))
            }

            lines.append("CPA \(nauticalMiles(cpa.distance))")
            lines.append(cpa.time > 0 ? "TCPA \(minutesSeconds(cpa.time))" : "TCPA NOW (OPENING)")
        } else {
            lines.append("CPA ---  (NO OWN OR TARGET COURSE)")
        }
        drawLabel(context, dial, lines: lines, near: targetPoint, bounds: bounds)
    }

    private func drawLabel(_ context: GraphicsContext, _ dial: DialGeometry, lines: [String], near point: CGPoint,
                           bounds: CGRect) {
        let text = context.resolve(
            Text(lines.joined(separator: "\n"))
                .font(.system(size: max(10, dial.radius * 0.04), weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        )
        let size = text.measure(in: CGSize(width: 400, height: 400))
        // Put the label on the side of the target away from the centre, so it does not cover the CPA
        // drawing (which runs from the centre). Near the edge, move it in only as far as needed to stay visible.
        let margin: CGFloat = 8
        var x = point.x >= dial.center.x ? point.x + 16 : point.x - 16 - size.width
        var y = point.y >= dial.center.y ? point.y + 16 : point.y - 16 - size.height
        x = min(max(x, bounds.minX + margin), bounds.maxX - margin - size.width)
        y = min(max(y, bounds.minY + margin), bounds.maxY - margin - size.height)
        let box = CGRect(x: x - 6, y: y - 4, width: size.width + 12, height: size.height + 8)
        // Night vision: black, as the window background (the system background is grey).
        context.fill(Path(box), with: isNightVision ? .color(.black) : .style(.background.opacity(0.9)))
        context.stroke(Path(box), with: .color(.secondary), lineWidth: 1)
        context.draw(text, in: CGRect(x: x, y: y, width: size.width, height: size.height))
    }

    private func nauticalMiles(_ metres: Double) -> String {
        String(format: metres < 1852 * 10 ? "%.2f NM" : "%.1f NM", metres / 1852)
    }

    private func minutesSeconds(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
