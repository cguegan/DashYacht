import BoatData
import SignalK
import SwiftUI

/// Three columns: instrument cards on each side, compass in the centre.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isNightVision) private var isNightVision
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var layout = model.layout
        // Fixed proportions: 16% cards, 68% compass, 16% cards.
        GeometryReader { geometry in
            let side = geometry.size.width * 0.16
            HStack(spacing: 0) {
                InstrumentColumn(cards: $layout.left, separatorEdge: .trailing, footer: .range)
                    .frame(width: side)
                CompassView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GridBackground())
                InstrumentColumn(cards: $layout.right, separatorEdge: .leading, footer: .appearance)
                    .frame(width: side)
            }
        }
        // Also under the window buttons, where the hidden title bar was.
        .background(HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision).background.ignoresSafeArea())
    }
}

struct InstrumentColumn: View {
    @Environment(AppModel.self) private var model
    @Binding var cards: [CardSettings]
    /// Side of the column that faces the compass.
    let separatorEdge: HorizontalEdge
    enum Footer { case range, appearance }
    /// Buttons at the bottom of the column: AIS range on the left, light/dark/night on the right.
    let footer: Footer
    @Environment(\.isNightVision) private var isNightVision
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Redraw every second even without new data, so values turn stale on time.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 13.5) {
                        ForEach($cards) { $card in
                            InstrumentCard(settings: $card, reading: reading(for: card, now: context.date))
                        }
                    }
                    .padding(14)
                }
                // The scroll view takes the free height, so the buttons stay at the bottom.
                Group {
                    switch footer {
                    case .range: RangeButtons()
                    case .appearance: AppearanceButtons()
                    }
                }
                .padding([.horizontal, .bottom], 14)
            }
        }
        .overlay(alignment: separatorEdge == .leading ? .leading : .trailing) {
            HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision).separator.opacity(0.5)
                .frame(width: 0.5)
        }
    }

    private func reading(for card: CardSettings, now: Date) -> Reading? {
        if let source = card.source {
            model.store.reading(source, now: now)
        } else {
            model.store.reading(card.instrument.paths, now: now)
        }
    }
}

/// One card: title and settings dot at the top, the value in the middle, the reference or source at the bottom.
struct InstrumentCard: View {
    @Binding var settings: CardSettings
    let reading: Reading?
    @State private var showsSettings = false
    @Environment(\.isNightVision) private var isNightVision
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let value = reading.flatMap { settings.instrument.value(of: $0, unit: settings.unit) }
        let isLive = reading?.isLive == true && value != nil
        let palette = HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision)
        let isPosition = value != nil && settings.instrument == .position

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(settings.instrument.title.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2.5)
                Spacer(minLength: 0)
                if let status = statusText {
                    Text(status)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.orange)
                }
                settingsDot(isLive: isLive, palette: palette)
            }
            Group {
                if let value, isPosition {
                    PositionReadout(lines: value.lines)
                } else {
                    ValueReadout(text: value?.lines.first ?? "—", unit: value?.unit ?? "",
                                 unitColor: unitColor(value, isLive: isLive))
                }
            }
            .foregroundStyle(isLive ? .primary : .tertiary)
            // Value centred; position right-aligned, so the hemispheres line up with the card edge.
            .frame(maxWidth: .infinity, alignment: isPosition ? .trailing : .center)
            .padding(.trailing, isPosition ? 2 : 0)
            .padding(.top, -2.5)
            Text((value?.detail ?? sourceText ?? " ").uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(2.5)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 14)
        .padding(.trailing, 11)
        .padding(.top, 5)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Faint fill and border: the cards stay quiet next to the compass.
            Self.shape.fill(.primary.opacity(0.05))
            Self.shape.stroke(palette.cardBorder.opacity(0.3), lineWidth: 1)
        }
    }

    /// Rounded except the top-right corner, where the settings dot is.
    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                                      bottomTrailingRadius: 14, topTrailingRadius: 0,
                                                      style: .continuous)

    /// Opens the settings of the card. Orange when the value is missing or old.
    private func settingsDot(isLive: Bool, palette: HUDPalette) -> some View {
        Button {
            showsSettings = true
        } label: {
            Circle()
                .fill(isLive ? palette.cardDot : .orange)
                .frame(width: 13, height: 13)
                .padding(2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Card settings")
        .accessibilityLabel("Settings of \(settings.instrument.name)")
        .popover(isPresented: $showsSettings, arrowEdge: .trailing) {
            CardSettingsView(settings: $settings)
                .appAppearance()
        }
    }

    private var statusText: String? {
        guard let reading else { return "NO DATA" }
        if case .stale(let age) = reading.freshness {
            return age < 120 ? "OLD \(Int(age))S" : "OLD \(Int(age / 60))MIN"
        }
        return nil
    }

    private var sourceText: String? {
        reading?.sample.sourceRef.map { "Source \($0)" }
    }

    private func unitColor(_ value: InstrumentValue?, isLive: Bool) -> Color? {
        // Night vision keeps only red: green would turn black, so the side is told by the text alone.
        guard isLive, !isNightVision, let side = value?.side else { return nil }
        let palette = HUDPalette(colorScheme: colorScheme, isNightVision: isNightVision)
        return side == .port ? palette.port : palette.starboard
    }
}

/// A number with its unit after it, for speeds, angles, depth, temperature and voltage.
struct ValueReadout: View {
    let text: String
    let unit: String
    /// `nil` uses the secondary colour.
    var unitColor: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(text)
                .font(.system(size: 44, weight: .medium).width(.condensed))
                .tracking(1.5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !unit.isEmpty {
                Text(unit.uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(unitColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            }
        }
    }
}

/// Latitude above longitude, right-aligned so the hemispheres line up.
struct PositionReadout: View {
    let lines: [String]

    var body: some View {
        // Two texts, so the lines can sit closer than one text allows. Each line shrinks on its own
        // when the card is too narrow, so the shorter one is padded at the front with figure spaces
        // (as wide as a digit): both then have the same length and shrink to the same size.
        let length = lines.map(\.count).max() ?? 0
        VStack(alignment: .trailing, spacing: -6) {
            ForEach(lines, id: \.self) { line in
                Text(String(repeating: "\u{2007}", count: length - line.count) + line)
                    .font(.system(size: 44, weight: .medium).width(.condensed))
                    .tracking(0.5)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Popover of the settings dot: instrument, source and unit of one card.
struct CardSettingsView: View {
    @Binding var settings: CardSettings
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Picker("Instrument", selection: Binding(get: { settings.instrument }, set: { settings.change(to: $0) })) {
                ForEach(Instrument.allCases, id: \.self) { instrument in
                    Text(instrument.name).tag(instrument)
                }
            }
            Picker("Source", selection: $settings.source) {
                Text("Automatic").tag(SourceSelection?.none)
                ForEach(sourceChoices, id: \.self) { source in
                    Text(label(source)).tag(Optional(source))
                }
            }
            if let defaultUnit = settings.instrument.units.first {
                Picker("Unit", selection: Binding(get: { settings.unit ?? defaultUnit }, set: { settings.unit = $0 })) {
                    ForEach(settings.instrument.units, id: \.self) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Sources received now, plus the chosen one if it has stopped sending (so the choice stays visible).
    private var sourceChoices: [SourceSelection] {
        let received = model.store.sources(for: settings.instrument.paths)
        guard let chosen = settings.source, !received.contains(chosen) else { return received }
        return received + [chosen]
    }

    private func label(_ source: SourceSelection) -> String {
        let name = source.sourceRef.map { "Source \($0)" } ?? "Unknown source"
        let missing = model.store.sources(for: [source.path]).contains(source) ? "" : " (no data)"
        return "\(name) · \(source.path)\(missing)"
    }
}
