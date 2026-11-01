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

/// The appearance choice, for the toolbar and the View menu.
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

/// Toolbar button that opens the appearance choice.
struct AppearanceMenu: View {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system

    var body: some View {
        Menu {
            AppearancePicker().pickerStyle(.inline)
        } label: {
            Label("Appearance", systemImage: mode.symbol)
        }
        .help("Appearance: \(mode.title)")
    }
}
