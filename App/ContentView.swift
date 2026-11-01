import SignalK
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isNightVision) private var isNightVision
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    @State private var showSourceSheet = false

    var body: some View {
        Group {
            if model.source == nil {
                ContentUnavailableView {
                    Label("No data source", systemImage: "sailboat")
                } description: {
                    Text("Connect to a Signal K server, or play the sample data.")
                } actions: {
                    Button("Choose Data Source…") { showSourceSheet = true }
                        .buttonStyle(.borderedProminent)
                    Button("Play Sample Data") { model.start(.sample) }
                }
            } else {
                DashboardView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        // Night vision hides the toolbar (too bright). The connection status must stay visible,
        // so it moves into the window, and a click on it opens the data source.
        .safeAreaInset(edge: .top, spacing: 0) {
            if isNightVision {
                HStack {
                    if let source = model.source {
                        Button { showSourceSheet = true } label: {
                            StatusView(source: source, status: model.status)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .help("Data Source")
                    } else {
                        Spacer()
                    }
                    // The toolbar is hidden in night vision, so this is the visible way back.
                    Button("Reset Colours", systemImage: "arrow.uturn.backward") { appearance = .system }
                        .help("Go back to the System appearance")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .toolbar(isNightVision ? .hidden : .visible, for: .windowToolbar)
        .navigationTitle(isNightVision ? "" : "DashYacht")
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let source = model.source {
                    StatusView(source: source, status: model.status)
                }
            }
            ToolbarItem {
                AppearanceMenu()
            }
            ToolbarItem {
                Button("Data Source", systemImage: "antenna.radiowaves.left.and.right") { showSourceSheet = true }
            }
        }
        .sheet(isPresented: $showSourceSheet) {
            SourceSheet()
                .appAppearance()
        }
    }
}

/// Connection state in the toolbar. Red or orange means the numbers on screen may be old.
struct StatusView: View {
    let source: DataSourceChoice
    let status: SourceStatus?
    @Environment(\.isNightVision) private var isNightVision

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(source.title).fontWeight(.medium)
            Text(detail).foregroundStyle(.secondary)
        }
        .font(.callout)
        .help(detail)
    }

    private var color: Color {
        switch status {
        // In night vision green turns black, so "connected" uses a dim dot and problems a bright one.
        case .connected: isNightVision ? .secondary : .green
        case .connecting, nil: .orange
        case .disconnected, .failed: .red
        }
    }

    private var detail: String {
        switch status {
        case .connected: "Connected"
        case .connecting, nil: "Connecting…"
        case .disconnected(let reason, let retryIn): "\(reason). Retry in \(retryIn) s"
        case .failed(let reason): reason
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
