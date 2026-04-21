import SwiftUI

/// Sheet for adding a new server or editing an existing one.
///
/// When adding a new server, shows a **picker screen** listing all 25 popular
/// networks. Selecting one pre-fills the form. "Custom Server" at the bottom
/// opens the full configuration form directly.
///
/// When editing an existing server, goes straight to the configuration form.
struct AddServerSheet: View {
    let existingServer: Server?
    let onSave: (Server) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // MARK: - Navigation state

    /// In add-new mode, start with the picker; jump to form once preset chosen.
    @State private var showPicker: Bool
    @State private var pickerSearch: String = ""

    init(existingServer: Server?, onSave: @escaping (Server) -> Void) {
        self.existingServer = existingServer
        self.onSave = onSave
        _showPicker = State(initialValue: existingServer == nil)
    }

    // MARK: - Form state (used in both picker-confirmation and edit mode)

    @State private var selectedPreset: PresetNetwork = .custom
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = "6697"
    @State private var useTLS: Bool = true
    @State private var nickname: String = ""
    @State private var realName: String = ""
    @State private var serverPassword: String = ""
    @State private var saslEnabled: Bool = false
    @State private var saslUsername: String = ""
    @State private var saslPassword: String = ""
    @State private var showAuthSection: Bool = false
    @State private var autoJoinChannels: [String] = []
    @State private var newChannelName: String = ""
    @State private var autoConnect: Bool = true
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var showGeneratedPassword = false
    /// The auto-generated password shown to the user for new server adds.
    @State private var generatedPassword: String = ""

    private var isEditing: Bool { existingServer != nil }
    private var port: Int { Int(portString) ?? 6697 }

    // MARK: - Body

    var body: some View {
        if showPicker {
            pickerScreen
        } else {
            formScreen
        }
    }

    // MARK: - Picker screen (list of 25 networks)

    private var filteredNetworks: [(Int, Server)] {
        let all = Array(Server.defaultNetworks.enumerated())
        guard !pickerSearch.isEmpty else { return all }
        return all.filter { _, s in
            s.name.localizedCaseInsensitiveContains(pickerSearch) ||
            s.host.localizedCaseInsensitiveContains(pickerSearch)
        }
    }

    private var pickerScreen: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredNetworks, id: \.0) { _, network in
                        Button {
                            applyPreset(PresetNetwork(host: network.host) ?? .custom)
                            name = network.name
                            host = network.host
                            portString = String(network.port)
                            useTLS = network.ssl
                            let globalNick = appState.globalNickname
                            nickname = globalNick.isEmpty ? Self.generateNick() : globalNick
                            realName = appState.globalRealName
                            if generatedPassword.isEmpty {
                                generatedPassword = Self.generatePassword()
                                serverPassword = generatedPassword
                            }
                            autoConnect = true
                            showPicker = false
                        } label: {
                            HStack(spacing: 12) {
                                // TLS lock icon
                                Image(systemName: network.ssl ? "lock.fill" : "lock.open")
                                    .font(.caption)
                                    .foregroundStyle(network.ssl ? .green : .orange)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(network.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(network.host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Popular IRC Networks")
                        .textCase(nil)
                }

                Section {
                    Button {
                        selectedPreset = .custom
                        let globalNick = appState.globalNickname
                        nickname = globalNick.isEmpty ? Self.generateNick() : globalNick
                        realName = appState.globalRealName
                        if generatedPassword.isEmpty {
                            generatedPassword = Self.generatePassword()
                            serverPassword = generatedPassword
                        }
                        autoConnect = true
                        showPicker = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom Server")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Enter host, port, and credentials manually")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $pickerSearch, prompt: "Search networks")
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Form screen (configuration detail)

    private var formScreen: some View {
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
                    Text("When enabled, Parso IRC connects to this server automatically each time you open the app.")
                }
            }
            .navigationTitle(isEditing ? "Edit Server" : (host.isEmpty ? "Custom Server" : name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button {
                            showPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.semibold))
                                Text("Networks")
                            }
                        }
                    }
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

    // MARK: - Form sections

    private var networkSection: some View {
        Section {
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

            // Display name
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
                Label("Nickname", systemImage: "person.fill")
                Spacer()
                TextField(appState.globalNickname.isEmpty ? "nickname" : appState.globalNickname,
                          text: $nickname)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            HStack {
                Label("Real Name", systemImage: "person.text.rectangle")
                Spacer()
                TextField(appState.globalRealName.isEmpty ? "Real Name" : appState.globalRealName,
                          text: $realName)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Identity")
        } footer: {
            Text("Leave blank to use your global identity from Settings.")
                .font(.caption)
        }
    }

    private var authSection: some View {
        if isEditing {
            // Edit mode: keep existing auth section in disclosure group
            return AnyView(Section {
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
                        HStack {
                            Label("SASL Password", systemImage: "key.fill")
                            Spacer()
                            SecureField("password", text: $saslPassword)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                    }
                }
            })
        } else {
            // New server: show auto-generated password prominently
            return AnyView(Section {
                // Generated password display
                HStack {
                    Label("Server Password", systemImage: "key.fill")
                    Spacer()
                    if showGeneratedPassword {
                        Text(generatedPassword)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else {
                        SecureField("Auto-generated", text: $serverPassword)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    Button {
                        showGeneratedPassword.toggle()
                    } label: {
                        Image(systemName: showGeneratedPassword ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        UIPasteboard.general.string = serverPassword.isEmpty ? generatedPassword : serverPassword
                        HapticManager.selectionFeedback()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

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
                    HStack {
                        Label("SASL Password", systemImage: "key.fill")
                        Spacer()
                        SecureField("password", text: $saslPassword)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("A unique password has been generated for this server. Save it somewhere safe or tap the copy icon — you can always change it in server settings.")
                    .font(.caption)
            })
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
        guard let s = existingServer else {
            // New server: use global identity + password if already set, otherwise generate
            let globalNick = appState.globalNickname
            nickname = globalNick.isEmpty ? Self.generateNick() : globalNick
            realName = appState.globalRealName
            // Prefer the global password from onboarding; generate one if not yet set
            let globalPw = appState.globalPassword
            if globalPw.isEmpty {
                generatedPassword = Self.generatePassword()
                serverPassword = generatedPassword
            } else {
                generatedPassword = globalPw
                serverPassword = globalPw
            }
            // Enable SASL by default so auth actually works on supported servers
            // NOTE: only enable SASL if the user intentionally sets a password here;
            // SASL requires the nick to be pre-registered with NickServ first.
            saslEnabled = false
            return
        }
        selectedPreset = PresetNetwork(host: s.host) ?? .custom
        name = s.name
        host = s.host
        portString = String(s.port)
        useTLS = s.ssl
        nickname = s.nickname
        realName = s.realname
        serverPassword = s.password ?? ""
        saslEnabled = s.saslEnabled
        saslUsername = s.nickname
        saslPassword = s.password ?? ""
        autoJoinChannels = s.channels.map(\.name)
        autoConnect = s.autoConnect
        showAuthSection = s.saslEnabled || !(s.password ?? "").isEmpty
    }

    /// Generates a random IRC-safe nickname like "parso1234".
    static func generateNick() -> String {
        "parso\(Int.random(in: 1000...9999))"
    }

    /// Generates a random 14-character alphanumeric password.
    static func generatePassword() -> String {
        let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<14).compactMap { _ in chars.randomElement() })
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
        if !autoJoinChannels.contains(ch) { autoJoinChannels.append(ch) }
        newChannelName = ""
    }

    private func attemptSave() {
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
            if !n.isEmpty { return n }
            if !appState.globalNickname.isEmpty { return appState.globalNickname }
            return Self.generateNick()
        }()

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
            nickname: resolvedNick,
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

#Preview {
    AddServerSheet(existingServer: nil) { _ in }
        .environmentObject(AppState.shared)
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
