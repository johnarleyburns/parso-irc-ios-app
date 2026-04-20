import SwiftUI

/// Channel browser sheet — sends LIST, streams results, lets user search and join.
///
/// Opens when the user taps "+ Join a channel" in the sidebar.
/// Fires `LIST` immediately on appear, then appends channels as RPL_LIST (322)
/// numerics arrive via `onUnhandledMessage`.  Results are searchable and sortable
/// client-side.  Tapping a row sends JOIN and dismisses.
struct ChannelBrowserSheet: View {
    let server: Server
    var onJoined: (() -> Void)? = nil

    @EnvironmentObject private var ircManager: IRCClientManager
    @Environment(\.dismiss) private var dismiss

    // LIST results
    @State private var channels: [ListEntry] = []
    @State private var isLoading = false
    @State private var listDone = false
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .members

    // Manual join fallback
    @State private var manualChannel = ""
    @State private var showManualJoin = false
    @State private var joinError: String? = nil

    // MARK: - Entry model

    struct ListEntry: Identifiable {
        let id: String       // channel name
        let name: String
        let members: Int
        let topic: String
    }

    enum SortOrder: String, CaseIterable {
        case members  = "Members"
        case name     = "Name"
        case topic    = "Topic"
    }

    // MARK: - Filtered + sorted

    private var filtered: [ListEntry] {
        let base = searchText.isEmpty ? channels :
            channels.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.topic.localizedCaseInsensitiveContains(searchText)
            }
        switch sortOrder {
        case .members: return base.sorted { $0.members > $1.members }
        case .name:    return base.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .topic:   return base.sorted { $0.topic.lowercased() < $1.topic.lowercased() }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && channels.isEmpty {
                    loadingView
                } else {
                    channelList
                }
            }
            .navigationTitle("Channels — \(server.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search channels")
            .toolbar { toolbarContent }
        }
        .onAppear { startList() }
        .onDisappear { deregister() }
        .alert("Join Error", isPresented: Binding(
            get: { joinError != nil },
            set: { if !$0 { joinError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(joinError ?? "")
        }
    }

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading channel list…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Channel list

    private var channelList: some View {
        List {
            // Manual join row at the top
            Section {
                Button {
                    showManualJoin = true
                } label: {
                    Label("Join by name…", systemImage: "number.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .sheet(isPresented: $showManualJoin) {
                    manualJoinSheet
                }
            }

            Section {
                ForEach(filtered) { entry in
                    channelRow(entry)
                }
            } header: {
                HStack {
                    Text("\(filtered.count) channel\(filtered.count == 1 ? "" : "s")")
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func channelRow(_ entry: ListEntry) -> some View {
        Button {
            joinChannel(entry.name)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(entry.members)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
                if !entry.topic.isEmpty {
                    Text(entry.topic)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Manual join sheet

    private var manualJoinSheet: some View {
        NavigationStack {
            Form {
                Section("Channel name") {
                    TextField("#channel", text: $manualChannel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Join Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showManualJoin = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        showManualJoin = false
                        joinChannel(manualChannel)
                    }
                    .disabled(manualChannel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                Divider()
                Button {
                    channels = []
                    listDone = false
                    startList()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    // MARK: - LIST request

    private func startList() {
        guard let client = ircManager.getClient(for: server.id) else { return }
        isLoading = true

        // Register callback to receive LIST replies
        client.onUnhandledMessage = { [weak ircManager] msg in
            Task { @MainActor in
                switch msg.command {
                case "321": // RPL_LISTSTART — nothing to do
                    break
                case "322": // RPL_LIST: params = [nick, channel, count, :topic]
                    guard msg.parameters.count >= 3 else { return }
                    let name  = msg.parameters[1]
                    let count = Int(msg.parameters[2]) ?? 0
                    let topic = msg.parameters.count > 3 ? msg.parameters[3] : ""
                    // Avoid duplicates
                    if !self.channels.contains(where: { $0.name == name }) {
                        self.channels.append(ListEntry(id: name, name: name, members: count, topic: topic))
                    }
                case "323": // RPL_LISTEND
                    self.isLoading = false
                    self.listDone = true
                default:
                    break
                }
            }
        }

        Task {
            try? await client.list()
        }
    }

    private func deregister() {
        ircManager.getClient(for: server.id)?.onUnhandledMessage = nil
    }

    // MARK: - JOIN

    private func joinChannel(_ rawName: String) {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !name.hasPrefix("#") && !name.hasPrefix("&") { name = "#\(name)" }

        Task {
            guard let client = ircManager.getClient(for: server.id) else {
                joinError = "Not connected to \(server.name)"
                return
            }
            do {
                try await client.join(channel: name)
                // Persist to DB
                let ch = Channel(serverId: server.id, name: name, joinedAt: Date())
                try? DatabaseManager.shared.saveChannel(ch, serverId: server.id)
                onJoined?()
                dismiss()
            } catch {
                joinError = error.localizedDescription
            }
        }
    }
}

#Preview {
    ChannelBrowserSheet(server: Server.defaultNetworks[0])
        .environmentObject(IRCClientManager.shared)
}
