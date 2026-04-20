import SwiftUI
import Combine

/// Channel browser — shows curated popular channels for known servers instantly,
/// lets users search by prefix (fires `LIST #query*`), or optionally loads the
/// full channel list with a warning popup.
///
/// Cache behaviour: results are stored in `IRCClientManager.channelListCache`
/// for the app's lifetime so re-opening the sheet is always instant.
/// The manager-level cache-population callbacks are saved and restored on dismiss
/// so the cache continues to populate even after the sheet is closed.
struct ChannelBrowserSheet: View {
    let server: Server
    /// Called with the channel name after a successful JOIN.
    var onJoined: ((String) -> Void)? = nil

    @EnvironmentObject private var ircManager: IRCClientManager
    @Environment(\.dismiss) private var dismiss

    // Display state
    @State private var searchText = ""
    @State private var searchResults: [ListEntry] = []
    @State private var isSearching = false      // prefix-search in flight
    @State private var isFullListLoading = false // full LIST in flight
    @State private var fullListLoaded = false
    @State private var allChannels: [ListEntry] = []   // populated by full LIST
    @State private var seenNames: Set<String> = []
    @State private var cacheDate: Date? = nil
    @State private var sortOrder: SortOrder = .members
    @State private var showFullListWarning = false

    // Inline join
    @State private var joinName = ""
    @State private var joinError: String? = nil

    // Debounce search
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    // Cache-safe handler references (saved before we overwrite, restored on dismiss)
    @State private var savedListEntryHandler: ((String, Int, String) -> Void)? = nil
    @State private var savedListEndHandler: (() -> Void)? = nil

    // MARK: - Models

    struct ListEntry: Identifiable {
        let id: String
        let name: String
        let members: Int
        let topic: String
    }

    enum SortOrder: String, CaseIterable {
        case members = "Members"
        case name    = "Name"
        case topic   = "Topic"
    }

    // MARK: - Curated popular channels per known server

    private static let popularChannels: [String: [String]] = [
        "irc.libera.chat":   ["#linux", "#python", "#debian", "#ubuntu", "#rust", "#archlinux", "#kde", "#bash", "#emacs", "#vim"],
        "irc.oftc.net":      ["#debian", "#ubuntu", "#tor", "#git", "#qemu", "#debian-next", "#postfix", "#notmuch", "#tor-dev", "#samba"],
        "irc.rizon.net":     ["#rice", "#chat", "#anime", "#programming", "#games", "#music", "#help", "#tech", "#random", "#offtopic"],
        "open.ircnet.net":   ["#chat", "#linux", "#windows", "#mp3", "#java", "#php", "#suomi", "#deutsch", "#france", "#help"],
        "irc.efnet.org":     ["#chat", "#linux", "#windows", "#games", "#mac", "#security", "#python", "#help", "#tech", "#programming"],
        "irc.quakenet.org":  ["#quake", "#quake4", "#games", "#chat", "#help", "#coding", "#counterstrike", "#warcraft", "#wow", "#fps"],
        "irc.undernet.org":  ["#chat", "#teen", "#help", "#linux", "#windows", "#games", "#music", "#movies", "#sports", "#politics"],
        "irc.dal.net":       ["#chat", "#music", "#games", "#movies", "#help", "#linux", "#windows", "#sports", "#anime", "#random"],
        "irc.hackint.org":   ["#ccc", "#hackint", "#tor", "#crypto", "#privacy", "#security", "#hardware", "#software", "#hacking", "#tech"],
        "irc.snoonet.org":   ["#gamesack", "#chat", "#politics", "#gaming", "#news", "#random", "#linux", "#tech", "#sports", "#anime"],
    ]

    private var curatedChannels: [String] {
        ChannelBrowserSheet.popularChannels[server.host] ?? []
    }

    // MARK: - Displayed list

    private var displayedEntries: [ListEntry] {
        let base: [ListEntry]
        if !searchText.isEmpty {
            base = searchResults
        } else if fullListLoaded {
            base = allChannels
        } else {
            // Show curated list as ListEntry stubs
            return curatedChannels.map { ListEntry(id: $0, name: $0, members: -1, topic: "") }
        }
        switch sortOrder {
        case .members: return base.sorted { $0.members > $1.members }
        case .name:    return base.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .topic:   return base.sorted { $0.topic.lowercased() < $1.topic.lowercased() }
        }
    }

    private var headerSubtitle: String {
        if isFullListLoading { return "Loading full list…" }
        if isSearching        { return "Searching…" }
        if fullListLoaded     { return "\(allChannels.count) channels · updated \(cacheDate?.timeAgo() ?? "")" }
        if !searchText.isEmpty { return "\(searchResults.count) results" }
        return "Popular channels"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // Quick-join by name
                quickJoinSection

                // Channel list
                Section {
                    ForEach(displayedEntries) { entry in
                        channelRow(entry)
                    }
                    if displayedEntries.isEmpty && !isSearching && !isFullListLoading {
                        emptyRow
                    }
                } header: {
                    HStack {
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                        Spacer()
                        if isSearching || isFullListLoading {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                }

                // Load full list button (only shown when not yet loaded)
                if !fullListLoaded && !isFullListLoading {
                    fullListButtonSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Join a Channel")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search \(server.name) channels")
            .toolbar { toolbarContent }
            .onChange(of: searchText) { _, newVal in
                handleSearchChange(newVal)
            }
        }
        .onAppear { restoreFromCacheIfAvailable() }
        .onDisappear { deregister() }
        .confirmationDialog(
            "Load Full Channel List?",
            isPresented: $showFullListWarning,
            titleVisibility: .visible
        ) {
            Button("Load Full List", role: .destructive) { startFullList() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Large servers like \(server.name) can have thousands of channels. Loading the full list may take several minutes and use significant data.")
        }
        .alert("Join Error", isPresented: Binding(
            get: { joinError != nil },
            set: { if !$0 { joinError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(joinError ?? "")
        }
    }

    // MARK: - Quick-join section

    private var quickJoinSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField("Channel name", text: $joinName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { joinChannel(joinName) }
                Button("Join") { joinChannel(joinName) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(joinName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Join by Name")
                .textCase(nil)
        }
    }

    // MARK: - Channel row

    private func channelRow(_ entry: ListEntry) -> some View {
        Button { joinChannel(entry.name) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !entry.topic.isEmpty {
                        Text(IRCTextFormatter.stripped(entry.topic))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if entry.members >= 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(entry.members)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyRow: some View {
        HStack {
            Spacer()
            Text(searchText.isEmpty ? "No channels" : "No matches for \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Full list button

    private var fullListButtonSection: some View {
        Section {
            Button {
                showFullListWarning = true
            } label: {
                HStack {
                    Image(systemName: "list.bullet.below.rectangle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Load Full Channel List")
                            .foregroundStyle(.primary)
                        Text("May take several minutes for large servers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
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
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    // MARK: - Search (debounced, prefix-filtered LIST)

    private func handleSearchChange(_ query: String) {
        searchDebounceTask?.cancel()
        if query.isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s debounce
            guard !Task.isCancelled else { return }
            await startPrefixSearch(query)
        }
    }

    @MainActor
    private func startPrefixSearch(_ query: String) {
        // If we have the full list cached, just filter locally — no network needed
        if fullListLoaded {
            searchResults = allChannels.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.topic.localizedCaseInsensitiveContains(query)
            }
            return
        }
        guard let client = ircManager.getClient(for: server.id) else { return }
        isSearching = true
        var localResults: [ListEntry] = []
        var localSeen: Set<String> = []

        client.onListEntry = { name, count, topic in
            Task { @MainActor in
                guard !localSeen.contains(name) else { return }
                localSeen.insert(name)
                localResults.append(ListEntry(id: name, name: name, members: count, topic: topic))
                self.searchResults = localResults
            }
        }
        client.onListEnd = {
            Task { @MainActor in
                self.isSearching = false
                // Re-wire manager-level cache handlers after our search completes
                self.rewireManagerHandlers()
            }
        }

        Task {
            try? await client.list(filter: query)
        }
    }

    // MARK: - Full list load

    private func startFullList() {
        guard let client = ircManager.getClient(for: server.id) else { return }
        isFullListLoading = true

        // Save manager-level handlers before we overwrite them
        savedListEntryHandler = client.onListEntry
        savedListEndHandler   = client.onListEnd

        client.onListEntry = { [self] name, count, topic in
            Task { @MainActor in
                guard !self.seenNames.contains(name) else { return }
                self.seenNames.insert(name)
                let entry = ListEntry(id: name, name: name, members: count, topic: topic)
                self.allChannels.append(entry)
                // Also populate manager cache staging buffer directly
                let cacheEntry = IRCClientManager.CachedListEntry(name: name, members: count, topic: topic)
                self.ircManager.appendToListStagingBuffer(serverId: self.server.id, entry: cacheEntry)
            }
        }
        client.onListEnd = {
            Task { @MainActor in
                self.isFullListLoading = false
                self.fullListLoaded = true
                // Commit to manager cache
                self.ircManager.commitListStagingBuffer(serverId: self.server.id)
                self.cacheDate = self.ircManager.channelListCache[self.server.id]?.fetchedAt
                // Re-wire manager-level handlers
                self.rewireManagerHandlers()
            }
        }

        Task { try? await client.list() }
    }

    // MARK: - Cache restore on appear

    private func restoreFromCacheIfAvailable() {
        if let cached = ircManager.channelListCache[server.id] {
            allChannels = cached.entries.map {
                ListEntry(id: $0.name, name: $0.name, members: $0.members, topic: $0.topic)
            }
            seenNames = Set(allChannels.map(\.name))
            cacheDate = cached.fetchedAt
            fullListLoaded = true
        }
    }

    // MARK: - Deregister (save/restore to preserve manager-level cache population)

    private func deregister() {
        searchDebounceTask?.cancel()
        guard let client = ircManager.getClient(for: server.id) else { return }
        // Restore previously-saved manager handlers, NOT nil
        if let saved = savedListEntryHandler { client.onListEntry = saved }
        if let saved = savedListEndHandler   { client.onListEnd   = saved }
    }

    private func rewireManagerHandlers() {
        guard let client = ircManager.getClient(for: server.id) else { return }
        if let saved = savedListEntryHandler { client.onListEntry = saved }
        if let saved = savedListEndHandler   { client.onListEnd   = saved }
        // Clear our local saves so a future search correctly re-saves the manager handlers
        savedListEntryHandler = nil
        savedListEndHandler   = nil
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
                let ch = Channel(serverId: server.id, name: name, joinedAt: Date())
                try? DatabaseManager.shared.saveChannel(ch, serverId: server.id)
                onJoined?(name)
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
