import BoatData
import SwiftUI

/// Discreet coastline behind the compass, heading-up and at the AIS range, to give an idea of the area.
/// From GSHHG (see NOTICE). Not for navigation.
struct ShorelineLayer: View, Animatable {
    /// Own position, `nil` when it is missing or old: then nothing is drawn.
    let position: Coordinate?
    let rangeMetres: Double
    /// True heading in degrees, animated with the compass card (as for the AIS targets).
    var rotation: Double

    nonisolated var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    var body: some View {
        // Built in the body (main actor) and only turned here, so the animation does not rebuild it.
        let coast = position.flatMap { ShorelineCache.shared.coast(around: $0, rangeMetres: rangeMetres) }
        Canvas { context, size in
            guard let coast, let position else { return }
            let dial = DialGeometry(size: size)
            let scale = dial.radius / rangeMetres
            let heading = rotation * .pi / 180
            let (sine, cosine) = (CGFloat(sin(heading)) * scale, CGFloat(cos(heading)) * scale)
            // Metres east and north of the boat → screen, turned so the bow is up.
            let boat = coast.frame.offset(of: position)
            var transform = CGAffineTransform(a: cosine, b: -sine, c: -sine, d: -cosine, tx: 0, ty: 0)
            transform.tx = dial.center.x - (transform.a * boat.x + transform.c * boat.y)
            transform.ty = dial.center.y - (transform.b * boat.x + transform.d * boat.y)

            context.clip(to: Path(ellipseIn: CGRect(x: dial.center.x - dial.radius, y: dial.center.y - dial.radius,
                                                    width: dial.radius * 2, height: dial.radius * 2)))
            context.stroke(coast.path.applying(transform), with: .color(.primary.opacity(0.3)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The shoreline file, its decoded cells, and the last coast built.
@MainActor
final class ShorelineCache {
    static let shared = ShorelineCache()

    struct Coast {
        /// Origin of the path: the boat position when it was built.
        let frame: LocalFrame
        let rangeMetres: Double
        /// Metres east (x) and north (y) of the origin.
        let path: Path
    }

    private let shoreline: Shoreline? = Bundle.main.url(forResource: "shoreline", withExtension: "dysl")
        .flatMap { try? Shoreline(data: Data(contentsOf: $0, options: .mappedIfSafe)) }
    private var cells: [Shoreline.Cell: [[Coordinate]]] = [:]
    private var built: Coast?

    /// Coast within reach of the dial. Rebuilt only when the range changes or the boat has moved
    /// a tenth of the range: building takes time, drawing a built path does not.
    func coast(around position: Coordinate, rangeMetres: Double) -> Coast? {
        if let built, built.rangeMetres == rangeMetres {
            let moved = built.frame.offset(of: position)
            if (moved * moved).sum().squareRoot() < rangeMetres * 0.1 { return built }
        }
        guard let shoreline else { return nil }
        // A bit more than the range, so the coast is complete until the next rebuild.
        let reach = rangeMetres * 1.3
        // Points closer than about one screen point add nothing.
        let tolerance = rangeMetres / 300
        let frame = LocalFrame(origin: position)
        let wanted = shoreline.cells(around: position, radius: reach)
        if cells.count > 64 { cells = cells.filter { wanted.contains($0.key) } }

        var path = Path()
        for cell in wanted {
            if cells[cell] == nil { cells[cell] = (try? shoreline.lines(in: cell)) ?? [] }
            for line in cells[cell] ?? [] {
                var last: SIMD2<Double>?
                for (index, coordinate) in line.enumerated() {
                    let point = frame.offset(of: coordinate)
                    // Far away: break the line, so long coasts out of reach cost nothing.
                    guard (point * point).sum().squareRoot() < reach else {
                        last = nil
                        continue
                    }
                    if let last {
                        let step = point - last
                        if (step * step).sum().squareRoot() < tolerance && index < line.count - 1 { continue }
                        path.addLine(to: CGPoint(x: point.x, y: point.y))
                    } else {
                        path.move(to: CGPoint(x: point.x, y: point.y))
                    }
                    last = point
                }
            }
        }
        let coast = Coast(frame: frame, rangeMetres: rangeMetres, path: path)
        built = coast
        return coast
    }
}
