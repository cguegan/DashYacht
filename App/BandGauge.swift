import BoatData
import SwiftUI

/// Band around the compass for a signed value: rudder angle at the bottom, rate of turn at the top,
/// engine RPM on each side. Centre is 0; starboard on the right, or ahead at the top for the side bands. The coloured bar fills continuously from the centre to the exact value.
/// `Animatable`, so SwiftUI moves the bar smoothly between two values.
struct BandGauge: View, Animatable {
    enum Placement {
        /// Rudder angle. The value is written under the band.
        case bottom
        /// Rate of turn. The value is written above the band.
        case top
        /// Port engine, ahead up. The value is written outside the band, level with 0.
        /// Needs a canvas wider than the dial, so the text has room beside it.
        case left
        /// Starboard engine, ahead up. The value is written outside the band, level with 0.
        case right
    }

    let placement: Placement
    /// Positive to starboard.
    var value: Double
    let hasValue: Bool
    let isLive: Bool
    /// Value at each end of the band.
    let scale: Double
    /// Text for the value, for example "RUDDER 21° S". Can have two lines.
    let label: String
    /// Bar colours below and above 0. `nil` uses port and starboard colours.
    var colors: (negative: Color, positive: Color)? = nil

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
                let colors = colors ?? (palette.port, palette.starboard)
                layer.stroke(bar, with: .color(value < 0 ? colors.negative : colors.positive),
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

            // One line at a time: a resolved text has no centre alignment for several lines.
            let lines = (isLive || !hasValue ? label : label + "  OLD").split(separator: "\n").map {
                context.resolve(
                    Text($0)
                        .font(.system(size: r * 0.055, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                )
            }
            let lineHeight = r * 0.07
            let anchorPoint: CGPoint
            var anchor = UnitPoint.center
            switch placement {
            case .bottom:
                anchorPoint = dial.point(180, r * 1.32)
            case .top:
                anchorPoint = dial.point(0, r * 1.32)
            case .left:
                anchorPoint = dial.point(270, r * 1.3)
                anchor = .trailing
            case .right:
                anchorPoint = dial.point(90, r * 1.3)
                anchor = .leading
            }
            for (index, line) in lines.enumerated() {
                let offset = (CGFloat(index) - CGFloat(lines.count - 1) / 2) * lineHeight
                context.draw(line, at: CGPoint(x: anchorPoint.x, y: anchorPoint.y + offset), anchor: anchor)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Compass angle of the middle of the band.
    private var centre: Double {
        switch placement {
        case .top: 0
        case .right: 90
        case .bottom: 180
        case .left: 270
        }
    }

    /// Compass angle of a value. Positive goes right at the top and bottom (clockwise at the top,
    /// anticlockwise at the bottom), and up on the sides (clockwise on the left, anticlockwise on the right).
    private func angle(of value: Double) -> Double {
        let clamped = min(max(value, -scale), scale)
        let offset = clamped / scale * Self.span
        switch placement {
        case .top, .left: return centre + offset
        case .bottom, .right: return centre - offset
        }
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
