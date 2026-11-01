import BoatData
import SwiftUI

/// Band around the compass for a value with a side: rudder angle at the bottom, rate of turn at the top.
/// Centre is 0, starboard on the right. The coloured bar fills continuously from the centre to the exact value.
/// `Animatable`, so SwiftUI moves the bar smoothly between two values.
struct BandGauge: View, Animatable {
    enum Placement {
        /// Rudder angle. The value is written under the band.
        case bottom
        /// Rate of turn. The value is written to the right of the heading box, which is above the band.
        case top
    }

    let placement: Placement
    /// Positive to starboard.
    var value: Double
    let hasValue: Bool
    let isLive: Bool
    /// Value at each end of the band.
    let scale: Double
    /// Text for the value, for example "RUD 21° S".
    let label: String

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    /// Half of the band, in compass degrees on each side of its centre.
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

            // Continuous bar from 0 to the value.
            if hasValue {
                let end = angle(of: value)
                let bar = arc(dial, from: min(centre, end), to: max(centre, end), radius: r * 1.16)
                layer.stroke(bar, with: .color(value < 0 ? palette.port : palette.starboard),
                             style: StrokeStyle(lineWidth: r * 0.08, lineCap: .butt))
            }

            // Scale ticks every tenth of the scale, drawn over the bar.
            var ticks = Path()
            for step in stride(from: -Self.span, through: Self.span, by: 3) where step != 0 {
                ticks.move(to: dial.point(centre + step, r * 1.12))
                ticks.addLine(to: dial.point(centre + step, r * 1.2))
            }
            layer.stroke(ticks, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            var zero = Path()
            zero.move(to: dial.point(centre, r * 1.1))
            zero.addLine(to: dial.point(centre, r * 1.24))
            layer.stroke(zero, with: .color(.primary), lineWidth: 2)

            // Pointer at the exact value, pointing at the dial.
            if hasValue {
                let position = angle(of: value)
                var pointer = Path()
                pointer.move(to: dial.point(position, r * 1.205))
                pointer.addLine(to: dial.point(position - 1.5, r * 1.26))
                pointer.addLine(to: dial.point(position + 1.5, r * 1.26))
                pointer.closeSubpath()
                layer.fill(pointer, with: .color(.primary))
            }

            let text = context.resolve(
                Text(isLive || !hasValue ? label : label + "  OLD")
                    .font(.system(size: r * 0.055, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            )
            switch placement {
            case .bottom:
                context.draw(text, at: dial.point(180, r * 1.32))
            case .top:
                let box = dial.headingBox
                context.draw(text, at: CGPoint(x: box.maxX + r * 0.04, y: box.midY), anchor: .leading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Compass angle of the middle of the band.
    private var centre: Double { placement == .bottom ? 180 : 0 }

    /// Compass angle of a value. Starboard is on the right: clockwise at the top, anticlockwise at the bottom.
    private func angle(of value: Double) -> Double {
        let clamped = min(max(value, -scale), scale)
        let offset = clamped / scale * Self.span
        return placement == .bottom ? centre - offset : centre + offset
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
