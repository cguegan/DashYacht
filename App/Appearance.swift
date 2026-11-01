import SwiftUI

/// Light, dark, or red night vision. Saved with `@AppStorage(AppearanceMode.storageKey)`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark, night

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .night: "Night Vision"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        case .night: "moon.stars.fill"
        }
    }

    /// `nil` follows the macOS setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .night: .dark
        }
    }
}

extension EnvironmentValues {
    /// In night vision every colour becomes a shade of red, so views must not rely on hue
    /// (green turns black). Views read this to use brightness instead.
    @Entry var isNightVision = false
}

/// Applies the chosen appearance. Use it on every window and sheet: sheets do not inherit it.
struct AppearanceModifier: ViewModifier {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system

    func body(content: Content) -> some View {
        content
            // The dark mode window background is grey, which still glows at night.
            .background {
                if mode == .night {
                    Color(white: 0.02).ignoresSafeArea()
                }
            }
            .preferredColorScheme(mode.colorScheme)
            .environment(\.isNightVision, mode == .night)
            // Dark mode with only the red channel kept: red light keeps the eyes adapted to the dark.
            .colorMultiply(mode == .night ? Color(red: 0.85, green: 0, blue: 0) : .white)
    }
}

extension View {
    func appAppearance() -> some View {
        modifier(AppearanceModifier())
    }
}

/// The appearance choice, for the View menu.
struct AppearancePicker: View {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system

    var body: some View {
        Picker("Appearance", selection: $mode) {
            ForEach(AppearanceMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbol).tag(mode)
            }
        }
    }
}

/// Light, dark and night vision buttons, at the top of the right panel. The selected one is highlighted.
/// "System" is only in the View menu: when it is chosen, no button is highlighted.
struct AppearanceButtons: View {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system

    var body: some View {
        HStack(spacing: 8) {
            ForEach([AppearanceMode.light, .dark, .night]) { choice in
                Button {
                    mode = choice
                } label: {
                    Image(systemName: choice.symbol)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(mode == choice ? .primary : .secondary)
                        .background(mode == choice ? AnyShapeStyle(.secondary.opacity(0.25)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.6), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(mode == choice ? .isSelected : [])
            }
        }
    }
}
