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

    init(colorScheme: ColorScheme, isNightVision: Bool) {
        if isNightVision {
            accent = .primary
            course = .primary
            wind = .primary
            port = .primary
            starboard = .primary
            ais = .primary
        } else if colorScheme == .dark {
            accent = .cyan
            course = Color(red: 1, green: 0.3, blue: 1)
            wind = .yellow
            port = .red
            starboard = .green
            ais = .green
        } else {
            accent = .blue
            course = .purple
            wind = .orange
            port = .red
            starboard = .green
            ais = Color(red: 0, green: 0.6, blue: 0)
        }
    }
}

/// Rectangle with the top-right corner cut, used for instrument cards.
struct ChamferedRectangle: Shape {
    var chamfer: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - chamfer, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + chamfer))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Small triangle that fills the cut corner of a `ChamferedRectangle`.
struct CornerMark: Shape {
    var size: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX - size, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + size))
            path.closeSubpath()
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
