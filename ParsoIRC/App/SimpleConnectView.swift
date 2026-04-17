import SwiftUI

struct SimpleConnectView: View {
    @State private var status: ConnectionStatus = .disconnected
    @State private var messages: [String] = []
    @State private var inputText: String = ""
    @State private var ircClient: IRCClient?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showDisconnectAlert = false
    @EnvironmentObject private var debugLog: DebugLogManager
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Libera.Chat")
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
                statusView
            }
            .padding()
            .background(Color(white: 0.1))
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, msg in
                            Text(msg)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.green)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
            
            // Input
            HStack {
                TextField("Enter command or message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    .onSubmit {
                        sendCommand()
                    }
                    .disabled(status != .connected)
                
                Button("Send") {
                    sendCommand()
                }
                .foregroundColor(.green)
                .disabled(status != .connected)
            }
            .padding()
            .background(Color(white: 0.1))
            
            // Debug Panel
            VStack(spacing: 0) {
                // Debug Header
                HStack {
                    Text("Debug Log")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Button("Clear") {
                        debugLog.clear()
                    }
                    .font(.caption)
                    .foregroundColor(.cyan)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.15))
                
                // Debug Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(debugLog.logs.enumerated()), id: \.element.id) { index, entry in
                                HStack(spacing: 4) {
                                    Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Color(red: 0, green: 1, blue: 1))
                                    
                                    Text("[\(entry.type.rawValue)]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(entry.type == .error ? Color(red: 1, green: 0.27, blue: 0.27) : Color(red: 1, green: 1, blue: 0))
                                    
                                    Text(entry.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onAppear {
                        if let lastId = debugLog.logs.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                    .onChange(of: debugLog.logs.count) { _, _ in
                        if let lastId = debugLog.logs.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(height: 200)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .alert("Disconnect from IRC?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                disconnect()
            }
        } message: {
            Text("Are you sure you want to disconnect from the IRC server?")
        }
    }
    
    @ViewBuilder
    var statusView: some View {
        switch status {
        case .disconnected:
            Button("Connect") {
                connect()
            }
            .foregroundColor(.green)
            .font(.headline)
            
        case .connecting:
            ProgressView()
                .scaleEffect(0.8)
            
        case .connected:
            Button {
                showDisconnectAlert = true
            } label: {
                Text("CONNECTED")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
            
        case .failed(let error):
            Text("FAILED")
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.2))
                .cornerRadius(4)
        }
    }
    
    private func connect() {
        status = .connecting
        messages.append("[Connecting to irc.libera.chat:6697...]")
        
        ircClient = IRCClient()
        guard let client = ircClient else {
            status = .failed("Failed to create client")
            return
        }
        
        let nickname = "parso\(Int.random(in: 1000...9999))"
        
        // MARK: PRIVMSG / NOTICE
        client.onMessage = { msg in
            let line: String
            switch msg.command {
            case "PRIVMSG":
                let from = msg.source?.nick ?? "unknown"
                let content = msg.parameters.count > 1 ? msg.parameters[1] : ""
                // Detect CTCP ACTION (\x01ACTION text\x01)
                if content.hasPrefix("\u{0001}ACTION ") && content.hasSuffix("\u{0001}") {
                    let action = content.dropFirst(8).dropLast()
                    line = "* \(from) \(action)"
                } else {
                    let target = msg.parameters.first ?? ""
                    if target.hasPrefix("#") || target.hasPrefix("&") {
                        line = "<\(from)> \(content)"
                    } else {
                        line = "[PM:\(from)] \(content)"
                    }
                }
            case "NOTICE":
                let from = msg.source?.nick ?? msg.source?.host ?? "server"
                let content = msg.parameters.count > 1 ? msg.parameters[1] : ""
                line = "-\(from)- \(content)"
            default:
                line = ":\(msg.source?.nick ?? "server") \(msg.command) \(msg.parameters.joined(separator: " "))"
            }
            Task { @MainActor in
                messages.append(line)
                scrollToBottom()
            }
        }
        
        // MARK: JOIN
        client.onJoin = { channel, nick in
            Task { @MainActor in
                messages.append("* \(nick) has joined \(channel)")
                scrollToBottom()
            }
        }
        
        // MARK: PART
        client.onPart = { channel, nick, reason in
            Task { @MainActor in
                if let reason = reason, !reason.isEmpty {
                    messages.append("* \(nick) has left \(channel) (\(reason))")
                } else {
                    messages.append("* \(nick) has left \(channel)")
                }
                scrollToBottom()
            }
        }
        
        // MARK: QUIT
        client.onQuit = { nick, reason in
            Task { @MainActor in
                if let reason = reason, !reason.isEmpty {
                    messages.append("* \(nick) has quit (\(reason))")
                } else {
                    messages.append("* \(nick) has quit")
                }
                scrollToBottom()
            }
        }
        
        // MARK: NICK
        client.onNickChange = { oldNick, newNick in
            Task { @MainActor in
                messages.append("* \(oldNick) is now known as \(newNick)")
                scrollToBottom()
            }
        }
        
        // MARK: TOPIC (live change)
        client.onTopicChange = { channel, topic, nick in
            Task { @MainActor in
                if topic.isEmpty {
                    messages.append("* \(nick) cleared the topic on \(channel)")
                } else {
                    messages.append("* \(nick) changed the topic on \(channel) to: \(topic)")
                }
                scrollToBottom()
            }
        }
        
        // MARK: NAMES LIST
        client.onNamesList = { channel, nicks in
            Task { @MainActor in
                messages.append("[NAMES] \(channel): \(nicks.joined(separator: " "))")
                scrollToBottom()
            }
        }
        
        // MARK: KICK
        client.onKick = { channel, kicked, by, reason in
            Task { @MainActor in
                if let reason = reason, !reason.isEmpty {
                    messages.append("* \(kicked) was kicked from \(channel) by \(by) (\(reason))")
                } else {
                    messages.append("* \(kicked) was kicked from \(channel) by \(by)")
                }
                scrollToBottom()
            }
        }
        
        // MARK: INVITE
        client.onInvite = { nick, channel in
            Task { @MainActor in
                messages.append("* \(nick) has invited you to \(channel)")
                scrollToBottom()
            }
        }
        
        // MARK: MODE
        client.onMode = { target, modeString, params in
            Task { @MainActor in
                let paramStr = params.isEmpty ? "" : " \(params.joined(separator: " "))"
                messages.append("* Mode \(modeString)\(paramStr) set on \(target)")
                scrollToBottom()
            }
        }
        
        // MARK: Welcome (001)
        client.onWelcome = { nick in
            Task { @MainActor in
                messages.append("* You are now known as \(nick)")
                status = .connected
                scrollToBottom()
            }
        }
        
        // MARK: Disconnect
        client.onDisconnect = {
            Task { @MainActor in
                messages.append("* Disconnected")
                status = .disconnected
                scrollToBottom()
            }
        }
        
        // MARK: Error
        client.onError = { error in
            Task { @MainActor in
                messages.append("* Error: \(error.localizedDescription)")
                status = .failed(error.localizedDescription)
                scrollToBottom()
            }
        }
        
        // MARK: Catch-all — server numerics and unhandled commands
        client.onUnhandledMessage = { [self] msg in
            debugLog.log("onUnhandledMessage: \(msg.command) \(msg.parameters.joined(separator: " "))", type: .info)
            let line = Self.formatServerMessage(msg)
            guard let line = line else {
                debugLog.log("formatServerMessage returned nil for: \(msg.command)", type: .info)
                return
            }
            debugLog.log("Displaying: \(line)", type: .info)
            Task { @MainActor in
                messages.append(line)
                scrollToBottom()
            }
        }
        
        Task {
            do {
                try await client.connect(
                    host: "irc.libera.chat",
                    port: 6697,
                    tls: true,
                    nickname: nickname,
                    username: "parso",
                    realname: "Parso IRC",
                    serverPassword: nil,
                    useSASL: false,
                    saslPassword: nil
                )
            } catch {
                await MainActor.run {
                    messages.append("* Connection failed: \(error.localizedDescription)")
                    status = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Server message formatting
    
    /// Returns a human-readable string for a server-sent message, or nil to suppress noisy internals.
    private static func formatServerMessage(_ msg: IRCMessage) -> String? {
        let cmd = msg.command
        // Extract the trailing (last) parameter, which is usually the human-readable text.
        // For numeric replies: params[0]=yournick, params[1..n-1]=data, params.last=text
        let text = msg.parameters.last ?? ""
        let source = msg.source?.nick ?? msg.source?.host ?? "server"
        
        switch cmd {
        // --- Connection registration numerics ---
        case "002": // RPL_YOURHOST
            return "[SERVER] \(text)"
        case "003": // RPL_CREATED
            return "[SERVER] \(text)"
        case "004": // RPL_MYINFO
            // params: [nick, servername, version, usermodes, chanmodes]
            let info = msg.parameters.dropFirst().joined(separator: " ")
            return "[SERVER] \(info)"
        case "005": // RPL_ISUPPORT
            // Drop nick (first) and the trailing "are supported..." message (last)
            let tokens = msg.parameters.dropFirst().dropLast().joined(separator: " ")
            return "[ISUPPORT] \(tokens)"
            
        // --- LUSERS ---
        case "251": // RPL_LUSERCLIENT
            return "[INFO] \(text)"
        case "252": // RPL_LUSEROP
            let count = msg.parameters.count > 1 ? msg.parameters[1] : "?"
            return "[INFO] \(count) IRC operators online"
        case "253": // RPL_LUSERUNKNOWN
            let count = msg.parameters.count > 1 ? msg.parameters[1] : "?"
            return "[INFO] \(count) unknown connections"
        case "254": // RPL_LUSERCHANNELS
            // params: [yournick, count, :channels formed]
            let count = msg.parameters.count > 1 ? msg.parameters[1] : "?"
            return "[INFO] \(count) channels formed"
        case "255": // RPL_LUSERME
            return "[INFO] \(text)"
        case "265": // RPL_LOCALUSERS
            return "[INFO] \(text)"
        case "266": // RPL_GLOBALUSERS
            return "[INFO] \(text)"
            
        // --- MOTD ---
        case "375": // RPL_MOTDSTART
            return "[MOTD] \(text)"
        case "372": // RPL_MOTD
            return "[MOTD] \(text)"
        case "376": // RPL_ENDOFMOTD
            return "[MOTD] End of MOTD"
        case "422": // ERR_NOMOTD
            return "[MOTD] No MOTD"
            
        // --- User mode on connect ---
        case "221": // RPL_UMODEIS
            let mode = msg.parameters.count > 1 ? msg.parameters[1] : text
            return "[MODE] Your user mode: \(mode)"
            
        // --- TOPIC numerics (after JOIN) ---
        case "331": // RPL_NOTOPIC
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : text
            return "[TOPIC] \(channel): No topic set"
        case "332": // RPL_TOPIC
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[TOPIC] \(channel): \(text)"
        case "333": // RPL_TOPICWHOTIME
            // params: [nick, channel, setter, timestamp]
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            let setter = msg.parameters.count > 2 ? msg.parameters[2] : "?"
            return "[TOPIC] \(channel) set by \(setter)"
            
        // --- NAMES ---
        case "366": // RPL_ENDOFNAMES
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : text
            return "[NAMES] End of list for \(channel)"
            
        // --- LIST ---
        case "321": // RPL_LISTSTART
            return "[LIST] Channels:"
        case "322": // RPL_LIST
            // params: [nick, channel, count, :topic]
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            let count = msg.parameters.count > 2 ? msg.parameters[2] : "?"
            if !text.isEmpty && msg.parameters.count > 3 {
                return "[LIST] \(channel): \(count) users — \(text)"
            }
            return "[LIST] \(channel): \(count) users"
        case "323": // RPL_LISTEND
            return "[LIST] End of channel list"
            
        // --- CHANNEL MODE ---
        case "324": // RPL_CHANNELMODEIS
            // params: [nick, channel, modestring, [modeparams...]]
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            let mode = msg.parameters.count > 2 ? msg.parameters[2] : ""
            let modeParams = msg.parameters.count > 3 ? " \(msg.parameters.dropFirst(3).joined(separator: " "))" : ""
            return "[MODE] \(channel): \(mode)\(modeParams)"
        case "329": // RPL_CREATIONTIME
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[INFO] \(channel) created \(text)"
            
        // --- WHOIS ---
        case "311": // RPL_WHOISUSER
            // params: [nick, target, user, host, *, :realname]
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            let user = msg.parameters.count > 2 ? msg.parameters[2] : ""
            let host = msg.parameters.count > 3 ? msg.parameters[3] : ""
            return "[WHOIS] \(target) (\(user)@\(host)): \(text)"
        case "312": // RPL_WHOISSERVER
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[WHOIS] \(target) via \(text)"
        case "313": // RPL_WHOISOPERATOR
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[WHOIS] \(target) is an IRC operator"
        case "317": // RPL_WHOISIDLE
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            let idle = msg.parameters.count > 2 ? msg.parameters[2] : "?"
            return "[WHOIS] \(target) idle: \(idle)s"
        case "318": // RPL_ENDOFWHOIS
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[WHOIS] End of WHOIS for \(target)"
        case "319": // RPL_WHOISCHANNELS
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[WHOIS] \(target) is on: \(text)"
        case "330": // RPL_WHOISACCOUNT
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            let account = msg.parameters.count > 2 ? msg.parameters[2] : text
            return "[WHOIS] \(target) is logged in as \(account)"
            
        // --- AWAY ---
        case "301": // RPL_AWAY
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[AWAY] \(target): \(text)"
        case "305": // RPL_UNAWAY
            return "[AWAY] You are no longer marked as away"
        case "306": // RPL_NOWAWAY
            return "[AWAY] You have been marked as away"
            
        // --- WHO ---
        case "315": // RPL_ENDOFWHO
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[WHO] End of WHO for \(target)"
        case "352": // RPL_WHOREPLY
            // params: [nick, channel, user, host, server, targetNick, flags, :hopcount realname]
            if msg.parameters.count >= 7 {
                let channel = msg.parameters[1]
                let targetNick = msg.parameters[6]
                let user = msg.parameters[2]
                let host = msg.parameters[3]
                return "[WHO] \(targetNick) (\(user)@\(host)) in \(channel)"
            }
            return "[WHO] \(text)"
            
        // --- SASL ---
        case "903": // RPL_SASLSUCCESS
            return "[SASL] Authentication successful"
        case "904": // ERR_SASLFAIL
            return "[SASL] Authentication failed"
        case "905": // ERR_SASLTOOLONG
            return "[SASL] SASL message too long"
        case "906": // ERR_SASLABORTED
            return "[SASL] SASL authentication aborted"
            
        // --- Nick errors ---
        case "431": // ERR_NONICKNAMEGIVEN
            return "[ERROR] No nickname given"
        case "432": // ERR_ERRONEUSNICKNAME
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Erroneous nickname: \(target)"
        case "433": // ERR_NICKNAMEINUSE
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Nickname \(target) is already in use"
        case "436": // ERR_NICKCOLLISION
            return "[ERROR] Nickname collision"
            
        // --- Channel errors ---
        case "401": // ERR_NOSUCHNICK
            let target = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] No such nick/channel: \(target)"
        case "403": // ERR_NOSUCHCHANNEL
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] No such channel: \(channel)"
        case "404": // ERR_CANNOTSENDTOCHAN
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Cannot send to channel \(channel): \(text)"
        case "405": // ERR_TOOMANYCHANNELS
            return "[ERROR] \(text)"
        case "421": // ERR_UNKNOWNCOMMAND
            let badCmd = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Unknown command: \(badCmd)"
        case "442": // ERR_NOTONCHANNEL
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] You are not on channel \(channel)"
        case "461": // ERR_NEEDMOREPARAMS
            let badCmd = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Not enough parameters for \(badCmd)"
        case "462": // ERR_ALREADYREGISTERED
            return "[ERROR] You may not re-register"
        case "464": // ERR_PASSWDMISMATCH
            return "[ERROR] Incorrect server password"
        case "465": // ERR_YOUREBANNEDCREEP
            return "[ERROR] You are banned from this server"
        case "471": // ERR_CHANNELISFULL
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Channel \(channel) is full"
        case "473": // ERR_INVITEONLYCHAN
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Channel \(channel) is invite-only"
        case "474": // ERR_BANNEDFROMCHAN
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] You are banned from \(channel)"
        case "475": // ERR_BADCHANNELKEY
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] Wrong channel key for \(channel)"
        case "482": // ERR_CHANOPRIVSNEEDED
            let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
            return "[ERROR] You're not channel operator on \(channel)"
            
        // --- INFO / VERSION ---
        case "351": // RPL_VERSION
            return "[VERSION] \(text)"
        case "371": // RPL_INFO
            return "[INFO] \(text)"
        case "374": // RPL_ENDOFINFO
            return "[INFO] End of INFO"
            
        // --- CAP (suppress from terminal — too noisy) ---
        case "CAP":
            return nil
            
        // --- PING / PONG (suppress — handled automatically) ---
        case "PING", "PONG":
            return nil
            
        // --- Fallback: show anything else generically ---
        default:
            // Suppress pure-numeric server housekeeping that has no user-facing text
            if let numericValue = Int(cmd), numericValue >= 200 && numericValue <= 210 {
                return nil
            }
            // For everything else show the trailing text if it's readable, otherwise raw
            if !text.isEmpty && text != source {
                return "[\(cmd)] \(text)"
            }
            let params = msg.parameters.dropFirst().joined(separator: " ")
            if params.isEmpty {
                return "[\(cmd)]"
            }
            return "[\(cmd)] \(params)"
        }
    }
    
    private func sendCommand() {
        guard !inputText.isEmpty, let client = ircClient else { return }
        
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append("→ \(cmd)")
        
        Task {
            do {
                try await client.send_raw(cmd)
            } catch {
                await MainActor.run {
                    messages.append("* Error sending: \(error.localizedDescription)")
                }
            }
        }
        
        inputText = ""
        dismissKeyboard()
    }
    
    private func disconnect() {
        guard let client = ircClient else { return }
        
        Task {
            await client.disconnect()
            await MainActor.run {
                messages.append("* Disconnected by user")
                status = .disconnected
                ircClient = nil
            }
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func scrollToBottom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                scrollProxy?.scrollTo(messages.count - 1, anchor: .bottom)
            }
        }
    }
}

#Preview {
    SimpleConnectView()
        .environmentObject(DebugLogManager.shared)
}
