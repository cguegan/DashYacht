import BoatData
import SwiftUI

/// Rudder angle on the band at the bottom of the compass: centre is 0°, starboard on the right.
/// The coloured bar fills continuously from the centre to the exact rudder angle.
/// `Animatable`, so SwiftUI moves the bar smoothly between two values.
struct RudderIndicator: View, Animatable {
    /// Degrees, positive to starboard (Signal K `steering.rudderAngle`).
    var angle: Double
    let hasValue: Bool
    let isLive: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    /// Largest rudder angle on the scale. Most rudders stop near 35°.
    static let scale = 35.0
    /// Half of the band, in compass degrees on each side of the bottom (180°).
    private static let span = 30.0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isNightVision) private var isNightVision

    var body: some View {
        let palette = HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision)
        Canvas { context, size in
            let dial = DialGeometry(size: size)
            let r = dial.radius
            var layer = context
            layer.opacity = hasValue && isLive ? 1 : 0.35

            // Continuous bar from 0° to the rudder angle.
            if hasValue {
                let clamped = min(max(angle, -Self.scale), Self.scale)
                let end = 180 - clamped / Self.scale * Self.span
                let bar = arc(dial, from: min(180, end), to: max(180, end), radius: r * 1.16)
                layer.stroke(bar, with: .color(angle < 0 ? palette.port : palette.starboard),
                             style: StrokeStyle(lineWidth: r * 0.08, lineCap: .butt))
            }

            // Scale ticks every 3.5° of rudder, drawn over the bar.
            var ticks = Path()
            for step in stride(from: -Self.span, through: Self.span, by: 3) where step != 0 {
                ticks.move(to: dial.point(180 - step, r * 1.12))
                ticks.addLine(to: dial.point(180 - step, r * 1.2))
            }
            layer.stroke(ticks, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            var centre = Path()
            centre.move(to: dial.point(180, r * 1.1))
            centre.addLine(to: dial.point(180, r * 1.24))
            layer.stroke(centre, with: .color(.primary), lineWidth: 2)

            // Pointer at the exact angle.
            if hasValue {
                let clamped = min(max(angle, -Self.scale), Self.scale)
                let position = 180 - clamped / Self.scale * Self.span
                var pointer = Path()
                pointer.move(to: dial.point(position, r * 1.205))
                pointer.addLine(to: dial.point(position - 1.5, r * 1.26))
                pointer.addLine(to: dial.point(position + 1.5, r * 1.26))
                pointer.closeSubpath()
                layer.fill(pointer, with: .color(.primary))
            }

            let value: String
            if hasValue {
                let rounded = Format.windAngle(angle * .pi / 180)
                value = abs(angle) < 0.5 ? "RUD 0°" : "RUD \(rounded.degrees)° \(rounded.side == .port ? "P" : "S")"
            } else {
                value = "RUD ---"
            }
            let text = context.resolve(
                Text(isLive || !hasValue ? value : value + "  OLD")
                    .font(.system(size: r * 0.055, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            )
            context.draw(text, at: dial.point(180, r * 1.32))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Arc between two compass angles, ending exactly at `end`.
    private func arc(_ dial: DialGeometry, from start: Double, to end: Double, radius: CGFloat) -> Path {
        Path { path in
            path.move(to: dial.point(start, radius))
            var angle = start
            while angle < end {
                angle = min(angle + 0.5, end)
                path.addLine(to: dial.point(angle, radius))
            }
        }
    }
}
