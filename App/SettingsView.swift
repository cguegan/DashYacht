import SwiftUI

/// Keys and defaults of the engine settings, shared by the settings window and the compass.
enum EngineSettings {
    static let maxRPMKey = "engine.maxRPM"
    static let defaultMaxRPM = 2000.0
}

/// The app settings window (DashYacht > Settings…).
struct SettingsView: View {
    @AppStorage(EngineSettings.maxRPMKey) private var maxRPM = EngineSettings.defaultMaxRPM

    var body: some View {
        Form {
            Section("Engines") {
                // Steps of 100 RPM; the band needs a positive end value.
                Stepper(value: $maxRPM, in: 500...8000, step: 100) {
                    LabeledContent("Maximum RPM", value: maxRPM.formatted(.number.precision(.fractionLength(0))))
                }
                Text("RPM at each end of the engine bands, ahead and astern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
