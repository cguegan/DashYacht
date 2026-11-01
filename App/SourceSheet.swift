import SignalK
import SwiftUI

struct SourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var servers: [DiscoveredServer] = []
    @State private var showFileImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Data Source").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Signal K server").font(.headline)
                HStack {
                    TextField("openplotter.local:3000", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(connect)
                    Button("Connect", action: connect)
                        .disabled(ServerAddress.streamURL(from: address) == nil)
                        .keyboardShortcut(.defaultAction)
                }
                if servers.isEmpty {
                    Text("Searching the network for Signal K servers…")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(servers) { server in
                        Button {
                            choose(.server(address: server.address))
                        } label: {
                            Label("\(server.name)  \(server.address)", systemImage: "server.rack")
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recorded data").font(.headline)
                HStack {
                    Button("Open Replay File…") { showFileImporter = true }
                    Button("Play Sample Data") { choose(.sample) }
                }
                Text("A replay file contains one Signal K delta (JSON) per line.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if case .server(let current)? = model.source { address = current }
        }
        .task {
            for await found in ServerBrowser.servers() { servers = found }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
            if case .success(let url) = result { choose(.replay(url)) }
        }
    }

    private func connect() {
        guard ServerAddress.streamURL(from: address) != nil else { return }
        choose(.server(address: address.trimmingCharacters(in: .whitespaces)))
    }

    private func choose(_ choice: DataSourceChoice) {
        model.start(choice)
        dismiss()
    }
}
