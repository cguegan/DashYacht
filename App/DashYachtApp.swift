import SwiftUI

@main
struct DashYachtApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .appAppearance()
        }
        // No title bar: the dashboard uses the whole window. Appearance and data source are in the menus.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                AppearancePicker()
            }
            CommandGroup(replacing: .newItem) {
                Button("Data Source…") { model.showsSourceSheet = true }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .appAppearance()
        }
    }
}
