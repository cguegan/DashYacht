import BoatData
import SwiftUI

/// Band around the compass for a signed value: rudder angle at the bottom, rate of turn at the top,
/// engine RPM on each side. Centre is 0; starboard on the right, or ahead at the top for the side bands.
/// The coloured bar fills continuously from the centre to the exact value. The triangle shows the value,
/// or a separate requested value (for the rudder: the angle asked by the autopilot).
/// `Animatable`, so SwiftUI moves the bar and the triangle smoothly between two values.
struct BandGauge: View, Animatable {
    enum Placement {
        /// Rudder angle. The value is written under the band.
        case bottom
        /// Rate of turn. The value is written above the band.
        case top
        /// Port engine, ahead up. The value is written in a box outside the band, level with 0.
        /// Needs a canvas wider than the dial, so the text has room beside it.
        case left
        /// Starboard engine, ahead up. The value is written in a box outside the band, level with 0.
        case right
    }

    let placement: Placement
    /// Positive to starboard.
    var value: Double
    let hasValue: Bool
    let isLive: Bool
    /// Shown faint although live, for example an engine in neutral: it turns but does not drive.
    var isDimmed = false
    /// Value at each end of the band.
    let scale: Double
    /// Text for the value, for example "RUDDER 21°". Can have several lines.
    let label: String
    /// Bar colours below and above 0. `nil` uses port and starboard colours.
    var colors: (negative: Color, positive: Color)? = nil

    enum Pointer {
        /// The triangle is at the value, at the end of the bar.
        case atValue
        /// The triangle is at `target`, a requested value. The bar shows what is really there.
        case atTarget
        /// No triangle, for example when no request is being sent.
        case hidden
    }

    var pointer = Pointer.atValue
    /// Requested value, used with `.atTarget`. Same unit and sign as `value`.
    var target = 0.0

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(value, target) }
        set {
            value = newValue.first
            target = newValue.second
        }
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
            layer.opacity = hasValue && isLive && !isDimmed ? 1 : 0.35

            // Continuous bar from 0 to the value.
            if hasValue {
                let end = angle(of: value)
                let bar = arc(dial, from: min(centre, end), to: max(centre, end), radius: r * 1.16)
                let colors = colors ?? (palette.port, palette.starboard)
                layer.stroke(bar, with: .color(value < 0 ? colors.negative : colors.positive),
                             style: StrokeStyle(lineWidth: r * 0.03, lineCap: .butt))
            }

            // Scale ticks every tenth of the scale, drawn over the bar.
            var ticks = Path()
            for step in stride(from: -Self.span, through: Self.span, by: 3) where step != 0 {
                ticks.move(to: dial.point(centre + step, r * 1.135))
                ticks.addLine(to: dial.point(centre + step, r * 1.185))
            }
            layer.stroke(ticks, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            var zero = Path()
            zero.move(to: dial.point(centre, r * 1.1))
            zero.addLine(to: dial.point(centre, r * 1.24))
            layer.stroke(zero, with: .color(.primary), lineWidth: 2)

            // Triangle pointing at the dial, at the value or at the requested value.
            let pointerValue: Double? = switch pointer {
            case .atValue: hasValue ? value : nil
            case .atTarget: target
            case .hidden: nil
            }
            if let pointerValue {
                let position = angle(of: pointerValue)
                var pointer = Path()
                pointer.move(to: dial.point(position, r * 1.205))
                pointer.addLine(to: dial.point(position - 1.5, r * 1.26))
                pointer.addLine(to: dial.point(position + 1.5, r * 1.26))
                pointer.closeSubpath()
                layer.fill(pointer, with: .color(.primary))
            }

            let font = Font.system(size: r * 0.055, weight: .semibold, design: .monospaced)
            let isSide = placement == .left || placement == .right
            // The side boxes have room for the RPM only: there an old value is shown by the grey text alone.
            let shown = isLive || !hasValue || isSide ? label : label + "  OLD"
            // One line at a time: a resolved text has no centre alignment for several lines.
            let lines = shown.split(separator: "\n").map {
                context.resolve(
                    Self.spaced(String($0), gap: r * 0.012)
                        .font(font)
                        .foregroundStyle(isLive && !isDimmed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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
            case .left, .right:
                // A box beside the 0 mark, wide enough for four digits and the thousands space,
                // so it keeps its size when the RPM changes.
                let digits = context.resolve(Self.spaced("8\u{202F}888", gap: r * 0.012).font(font))
                    .measure(in: CGSize(width: r, height: r))
                let size = CGSize(width: digits.width + r * 0.08, height: digits.height + r * 0.04)
                let edge = dial.point(centre, r * 1.3)
                let box = CGRect(x: placement == .left ? edge.x - size.width : edge.x, y: edge.y - size.height / 2,
                                 width: size.width, height: size.height)
                // The 0 mark runs on to the box.
                var link = Path()
                link.move(to: dial.point(centre, r * 1.24))
                link.addLine(to: edge)
                layer.stroke(link, with: .color(.primary), lineWidth: 2)
                let shape = RoundedRectangle(cornerRadius: r * 0.025).path(in: box)
                let fill: GraphicsContext.Shading = isNightVision ? .color(.black)
                    : palette.background.map { .color($0) } ?? .style(.background)
                context.fill(shape, with: fill)
                context.stroke(shape, with: .color(isDimmed ? .secondary : .primary), lineWidth: 1.5)
                anchorPoint = CGPoint(x: box.midX, y: box.midY)
            }
            for (index, line) in lines.enumerated() {
                let offset = (CGFloat(index) - CGFloat(lines.count - 1) / 2) * lineHeight
                context.draw(line, at: CGPoint(x: anchorPoint.x, y: anchorPoint.y + offset), anchor: anchor)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Text where a narrow space (thousands, as in "1 634") becomes a small gap after the digit before it.
    /// In a monospaced font the space itself is almost as wide as a digit, too wide for "slight".
    private static func spaced(_ text: String, gap: CGFloat) -> Text {
        let parts = text.split(separator: "\u{202F}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return Text(text) }
        return Text(String(parts[0].dropLast())) + Text(String(parts[0].suffix(1))).kerning(gap) + Text(String(parts[1]))
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
