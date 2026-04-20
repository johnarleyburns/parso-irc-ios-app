import SwiftUI

/// Form sheet for adding a new server or editing an existing one.
///
/// - `existingServer`: pass a `Server` to pre-fill the form for editing, or
///   `nil` when creating a new one.
/// - `onSave`: called with the saved `Server` after the user taps Connect/Save.
///   The caller is responsible for dismissing the sheet.
struct AddServerSheet: View {
    let existingServer: Server?
    let onSave: (Server) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state

    @State private var selectedPreset: PresetNetwork = .custom
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = "6697"
    @State private var useTLS: Bool = true

    // Identity (overrides the global default if non-empty)
    @State private var nickname: String = ""
    @State private var realName: String = ""

    // Auth
    @State private var serverPassword: String = ""
    @State private var saslEnabled: Bool = false
    @State private var saslUsername: String = ""
    @State private var saslPassword: String = ""
    @State private var showAuthSection: Bool = false

    // Auto-join channels
    @State private var autoJoinChannels: [String] = []
    @State private var newChannelName: String = ""

    // Connection behaviour
    @State private var autoConnect: Bool = true

    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    private var isEditing: Bool { existingServer != nil }
    private var port: Int { Int(portString) ?? 6697 }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                networkSection
                identitySection
                authSection
                channelsSection
                Section {
                    Toggle("Auto-connect on launch", isOn: $autoConnect)
                        .tint(.accentColor)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("When enabled, Parso IRC will connect to this server automatically each time you open the app.")
                }
            }
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Connect") { attemptSave() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Check Your Settings", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: - Sections

    private var networkSection: some View {
        Section {
            // Preset picker
            Picker("Network", selection: $selectedPreset) {
                ForEach(PresetNetwork.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: selectedPreset) { _, preset in applyPreset(preset) }

            // Host
            HStack {
                Label("Host", systemImage: "network")
                Spacer()
                TextField("irc.example.net", text: $host)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            // Port
            HStack {
                Label("Port", systemImage: "number")
                Spacer()
                TextField("6697", text: $portString)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
            }

            // TLS toggle
            Toggle(isOn: $useTLS) {
                Label("Use TLS / SSL", systemImage: "lock.fill")
            }
            .tint(.green)
            .onChange(of: useTLS) { _, tls in
                if portString == "6667" && tls { portString = "6697" }
                if portString == "6697" && !tls { portString = "6667" }
            }

            // Display name (auto-derived but editable)
            HStack {
                Label("Display Name", systemImage: "tag")
                Spacer()
                TextField("My Server", text: $name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Network")
        } footer: {
            Text("Standard ports: 6697 (TLS) · 6667 (plain)")
                .font(.caption)
        }
    }

    private var identitySection: some View {
        Section {
            HStack {
                Label("Nickname", systemImage: "person")
                Spacer()
                TextField(appState.globalNickname.isEmpty ? "nick" : appState.globalNickname,
                          text: $nickname)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Label("Real Name", systemImage: "person.text.rectangle")
                Spacer()
                TextField(appState.globalRealName.isEmpty ? "Parso IRC" : appState.globalRealName,
                          text: $realName)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Identity")
        } footer: {
            Text("Leave blank to use your global default.")
                .font(.caption)
        }
    }

    private var authSection: some View {
        Section {
            DisclosureGroup("Authentication", isExpanded: $showAuthSection) {
                SecureField("Server Password (optional)", text: $serverPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Toggle("SASL Authentication", isOn: $saslEnabled)
                    .tint(.accentColor)

                if saslEnabled {
                    HStack {
                        Label("SASL Username", systemImage: "person.badge.key")
                        Spacer()
                        TextField("username", text: $saslUsername)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    SecureField("SASL Password", text: $saslPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var channelsSection: some View {
        Section {
            ForEach(autoJoinChannels, id: \.self) { channel in
                HStack {
                    Text(channel)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                }
            }
            .onDelete { offsets in
                autoJoinChannels.remove(atOffsets: offsets)
            }

            HStack {
                TextField("#channel", text: $newChannelName)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { addChannel() }
                Button("Add") { addChannel() }
                    .foregroundStyle(Color.accentColor)
                    .disabled(newChannelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Auto-join Channels")
        } footer: {
            Text("These channels will be joined automatically on connect.")
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private func prefill() {
        if let s = existingServer {
            // Edit mode: fill all fields from existing server
            selectedPreset = PresetNetwork(host: s.host) ?? .custom
            name = s.name
            host = s.host
            portString = String(s.port)
            useTLS = s.ssl
            nickname = s.nickname
            realName = s.realname
            serverPassword = s.password ?? ""
            saslEnabled = s.saslEnabled
            saslUsername = s.nickname  // SASL username is often the nick (TODO: store separately)
            saslPassword = s.password ?? ""
            autoJoinChannels = s.channels.map(\.name)
            autoConnect = s.autoConnect
            showAuthSection = s.saslEnabled || !(s.password ?? "").isEmpty
        } else {
            // New server: apply global defaults
            nickname = appState.globalNickname
            realName = appState.globalRealName
            autoConnect = true
            // Default to Libera.Chat
            applyPreset(.libera)
        }
    }

    private func applyPreset(_ preset: PresetNetwork) {
        guard preset != .custom else { return }
        host = preset.host
        portString = String(preset.port)
        useTLS = preset.tls
        if name.isEmpty || PresetNetwork.allCases.contains(where: { $0.displayName == name }) {
            name = preset.displayName
        }
    }

    private func addChannel() {
        var ch = newChannelName.trimmingCharacters(in: .whitespaces)
        guard !ch.isEmpty else { return }
        if !ch.hasPrefix("#") && !ch.hasPrefix("&") { ch = "#" + ch }
        if !autoJoinChannels.contains(ch) {
            autoJoinChannels.append(ch)
        }
        newChannelName = ""
    }

    private func attemptSave() {
        // Validation
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else {
            validationMessage = "Please enter a server host name."
            showValidationAlert = true
            return
        }
        guard port > 0 && port <= 65535 else {
            validationMessage = "Port must be between 1 and 65535."
            showValidationAlert = true
            return
        }

        let resolvedNick: String = {
            let n = nickname.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? appState.globalNickname : n
        }()
        let finalNick = resolvedNick.isEmpty ? "parso\(Int.random(in: 1000...9999))" : resolvedNick

        let resolvedReal: String = {
            let r = realName.trimmingCharacters(in: .whitespaces)
            return r.isEmpty ? appState.globalRealName : r
        }()

        let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? h : name.trimmingCharacters(in: .whitespaces)
        let channels = autoJoinChannels.map { Channel(name: $0) }

        let server = Server(
            id: existingServer?.id ?? UUID().uuidString,
            name: displayName,
            host: h,
            port: port,
            ssl: useTLS,
            nickname: finalNick,
            realname: resolvedReal.isEmpty ? "Parso IRC" : resolvedReal,
            password: serverPassword.isEmpty ? nil : serverPassword,
            saslEnabled: saslEnabled,
            saslMechanism: "PLAIN",
            autoConnect: autoConnect,
            createdAt: existingServer?.createdAt ?? Date(),
            channels: channels,
            lastActiveChannel: channels.first?.name
        )

        do {
            try DatabaseManager.shared.saveServer(server)
            onSave(server)
            dismiss()
        } catch {
            validationMessage = "Could not save server: \(error.localizedDescription)"
            showValidationAlert = true
        }
    }
}

// MARK: - Preset networks

enum PresetNetwork: String, CaseIterable, Identifiable {
    case libera, oftc, rizon, ircnet, efnet, quakenet, undernet, dalnet, hackint, snoonet,
         twoSixHundredNet, tildechat, freenode, geekshed, gamesurge, irchighway,
         chatjunkies, allnetwork, p2pnet, sorcerynet,
         ircam, digitalized, pirc, anonops, austnet,
         custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .libera:         return "Libera.Chat"
        case .oftc:           return "OFTC"
        case .rizon:          return "Rizon"
        case .ircnet:         return "IRCnet"
        case .efnet:          return "EFnet"
        case .quakenet:       return "QuakeNet"
        case .undernet:       return "Undernet"
        case .dalnet:         return "DALnet"
        case .hackint:        return "hackint"
        case .snoonet:        return "Snoonet"
        case .twoSixHundredNet: return "2600net"
        case .tildechat:      return "tilde.chat"
        case .freenode:       return "Freenode"
        case .geekshed:       return "GeekShed"
        case .gamesurge:      return "GameSurge"
        case .irchighway:     return "IRCHighway"
        case .chatjunkies:    return "ChatJunkies"
        case .allnetwork:     return "AllNetwork"
        case .p2pnet:         return "P2P-NET"
        case .sorcerynet:     return "SorceryNet"
        case .ircam:          return "IRCAM"
        case .digitalized:    return "Digitalized"
        case .pirc:           return "PIRC"
        case .anonops:        return "AnonOps"
        case .austnet:        return "Austnet"
        case .custom:         return "Custom…"
        }
    }

    var host: String {
        switch self {
        case .libera:         return "irc.libera.chat"
        case .oftc:           return "irc.oftc.net"
        case .rizon:          return "irc.rizon.net"
        case .ircnet:         return "open.ircnet.net"
        case .efnet:          return "irc.efnet.org"
        case .quakenet:       return "irc.quakenet.org"
        case .undernet:       return "irc.undernet.org"
        case .dalnet:         return "irc.dal.net"
        case .hackint:        return "irc.hackint.org"
        case .snoonet:        return "irc.snoonet.org"
        case .twoSixHundredNet: return "irc.2600.net"
        case .tildechat:      return "irc.tilde.chat"
        case .freenode:       return "irc.freenode.net"
        case .geekshed:       return "irc.geekshed.net"
        case .gamesurge:      return "irc.gamesurge.net"
        case .irchighway:     return "irc.irchighway.net"
        case .chatjunkies:    return "irc.chatjunkies.org"
        case .allnetwork:     return "irc.allnetwork.org"
        case .p2pnet:         return "irc.p2p-irc.net"
        case .sorcerynet:     return "irc.sorcery.net"
        case .ircam:          return "irc.ircam.fr"
        case .digitalized:    return "irc.digitalized.tv"
        case .pirc:           return "pirc.at"
        case .anonops:        return "irc.anonops.com"
        case .austnet:        return "irc.austnet.org"
        case .custom:         return ""
        }
    }

    var port: Int {
        switch self {
        case .libera, .oftc, .rizon, .hackint, .snoonet,
             .twoSixHundredNet, .tildechat, .freenode, .geekshed,
             .irchighway, .chatjunkies, .allnetwork, .p2pnet, .sorcerynet,
             .ircam, .digitalized, .pirc, .anonops:
            return 6697
        default:
            return 6667
        }
    }

    var tls: Bool { port == 6697 }

    init?(host: String) {
        if let match = PresetNetwork.allCases.first(where: { $0.host == host && $0 != .custom }) {
            self = match
        } else {
            return nil
        }
    }
}

#Preview {
    AddServerSheet(existingServer: nil) { _ in }
        .environmentObject(AppState.shared)
}
