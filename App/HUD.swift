import SwiftUI

/// Colours of the instrument display. Night vision keeps only the red channel, so every
/// colour used there must contain red (cyan and green would turn black).
struct HUDPalette {
    var accent: Color
    var course: Color
    var wind: Color
    var port: Color
    var starboard: Color
    var ais: Color
    /// Behind the dashboard. `nil` keeps the window background.
    var background: Color?
    var cardBorder: Color
    /// Settings dot of a card with a live value.
    var cardDot: Color
    /// Line between a card column and the compass.
    var separator: Color

    init(colorScheme: ColorScheme, isNightVision: Bool) {
        if isNightVision {
            accent = .primary
            course = .primary
            wind = .primary
            port = .primary
            starboard = .primary
            ais = .primary
            background = nil
            cardBorder = .secondary.opacity(0.6)
            cardDot = .secondary.opacity(0.35)
            separator = .secondary.opacity(0.4)
        } else if colorScheme == .dark {
            accent = .cyan
            course = Color(red: 1, green: 0.3, blue: 1)
            wind = .yellow
            port = .red
            starboard = .green
            ais = .green
            background = Color(red: 0x02 / 255, green: 0x19 / 255, blue: 0x1F / 255)
            cardBorder = Color(red: 0x94 / 255, green: 0x9A / 255, blue: 0x9D / 255)
            cardDot = Color(red: 0x21 / 255, green: 0x34 / 255, blue: 0x38 / 255)
            separator = Color(red: 0x62 / 255, green: 0x6E / 255, blue: 0x71 / 255)
        } else {
            accent = .blue
            course = .purple
            wind = .orange
            port = .red
            starboard = .green
            ais = Color(red: 0, green: 0.6, blue: 0)
            background = nil
            cardBorder = .secondary.opacity(0.6)
            cardDot = .secondary.opacity(0.35)
            separator = .secondary.opacity(0.4)
        }
    }
}

/// Faint grid of "+" marks behind the dashboard.
struct GridBackground: View {
    var spacing: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            var marks = Path()
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    marks.move(to: CGPoint(x: x - 3, y: y))
                    marks.addLine(to: CGPoint(x: x + 3, y: y))
                    marks.move(to: CGPoint(x: x, y: y - 3))
                    marks.addLine(to: CGPoint(x: x, y: y + 3))
                }
            }
            context.stroke(marks, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
