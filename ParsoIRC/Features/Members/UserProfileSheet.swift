import SwiftUI

/// A half-sheet profile card for a channel member.
///
/// Immediately shows whatever we already know (nick, mode, host) then
/// fires a WHOIS query when it appears and populates additional fields
/// as the server's numeric replies arrive via `onUnhandledMessage`.
///
/// Actions:
///   "Mention" — inserts "nick: " into the chat input bar
///   "Send Message" — future Phase 4 DM (stub for now)
///   "WHOIS" — re-fires the query to refresh info
struct UserProfileSheet: View {
    let nick: String
    let member: ChannelMember?
    let serverId: String

    var onMention: ((String) -> Void)? = nil
    /// Called when the user taps "Send Direct Message". Provides (nick, serverId).
    var onDM: ((String, String) -> Void)? = nil

    @EnvironmentObject private var ircManager: IRCClientManager
    @Environment(\.dismiss) private var dismiss

    // WHOIS state — populated as numerics arrive
    @State private var realName: String? = nil
    @State private var userHost: String? = nil
    @State private var serverInfo: String? = nil
    @State private var idleSecs: Int? = nil
    @State private var channels: [String] = []
    @State private var account: String? = nil
    @State private var isOperator: Bool = false
    @State private var isSecure: Bool = false
    @State private var isLoadingWhois: Bool = false
    @State private var whoisDone: Bool = false

    // Saved handler — restored when this sheet closes so ChatView's topic feed keeps working
    private var _savedUnhandledHandler: ((IRCMessage) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero header
                    heroHeader

                    Divider()
                        .padding(.vertical, 8)

                    // WHOIS info rows
                    if isLoadingWhois && !whoisDone {
                        HStack {
                            ProgressView()
                            Text("Loading info…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    } else {
                        whoisInfoRows
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Action buttons
                    actionButtons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle(nick)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        whoisDone = false
                        fireWhois()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { fireWhois() }
        .onDisappear { deregisterWhoisCallback() }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 12) {
            // Large avatar
            ZStack(alignment: .bottomTrailing) {
                AvatarView(nick: nick, size: 80, showBorder: false)
                    .shadow(color: NickColorGenerator.color(for: nick).opacity(0.4), radius: 8, y: 4)

                if member?.isAway == true {
                    Image(systemName: "moon.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color(.systemOrange)))
                }
            }
            .padding(.top, 20)

            // Nick + mode badge
            HStack(spacing: 8) {
                if let mode = member?.mode, mode != .none {
                    Text(mode.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(MemberRowView.modeColor(mode).opacity(0.2))
                        )
                        .foregroundStyle(MemberRowView.modeColor(mode))
                }

                Text(nick)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(NickColorGenerator.color(for: nick))
            }

            // Real name below nick
            if let real = realName {
                Text(real)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Badges row
            HStack(spacing: 8) {
                if isOperator {
                    badge("IRC Operator", icon: "person.badge.shield.checkmark", color: .green)
                }
                if isSecure {
                    badge("Secure", icon: "lock.fill", color: .blue)
                }
                if member?.isAway == true {
                    badge("Away", icon: "moon.fill", color: .orange)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - WHOIS info rows

    @ViewBuilder
    private var whoisInfoRows: some View {
        VStack(spacing: 0) {
            if let uh = userHost {
                infoRow(label: "Address", value: uh, icon: "network")
            }
            if let srv = serverInfo {
                infoRow(label: "Server", value: srv, icon: "server.rack")
            }
            if let acc = account {
                infoRow(label: "Account", value: acc, icon: "person.crop.circle.badge.checkmark")
            }
            if let idle = idleSecs {
                infoRow(label: "Idle", value: formatIdle(idle), icon: "clock")
            }
            if !channels.isEmpty {
                infoRow(label: "Channels", value: channels.joined(separator: " "), icon: "number")
            }
        }
        .padding(.horizontal, 4)
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Mention
            Button {
                onMention?(nick)
            } label: {
                Label("Mention in Chat", systemImage: "at")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Send DM
            Button {
                onDM?(nick, serverId)
                dismiss()
            } label: {
                Label("Send Direct Message", systemImage: "envelope")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Badge helper

    private func badge(_ label: String, icon: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - WHOIS

    private func fireWhois() {
        guard let client = ircManager.getClient(for: serverId) else { return }
        isLoadingWhois = true
        whoisDone = false

        // Save the existing handler so we can restore it when the sheet closes,
        // preventing this WHOIS observer from permanently severing ChatView's topic feed.
        let existing = client.onUnhandledMessage
        client.onUnhandledMessage = { [nick] ircMsg in
            Task { @MainActor in
                self.handleWhoisNumeric(ircMsg, for: nick)
            }
        }

        Task {
            try? await client.whois(nick)
        }

        // Store existing so deregister can restore it
        _savedUnhandledHandler = existing
    }

    private func handleWhoisNumeric(_ msg: IRCMessage, for targetNick: String) {
        switch msg.command {
        case "311": // RPL_WHOISUSER  nick user host * :realname
            guard msg.parameters.count >= 4 else { return }
            guard msg.parameters[1].lowercased() == targetNick.lowercased() else { return }
            let user = msg.parameters[2]
            let host = msg.parameters[3]
            userHost = "\(user)@\(host)"
            realName = msg.parameters.last

        case "312": // RPL_WHOISSERVER  nick server :info
            guard msg.parameters.count >= 3 else { return }
            guard msg.parameters[1].lowercased() == targetNick.lowercased() else { return }
            serverInfo = "\(msg.parameters[2]) — \(msg.parameters.last ?? "")"

        case "313": // RPL_WHOISOPERATOR
            guard msg.parameters.count >= 2 else { return }
            guard msg.parameters[1].lowercased() == targetNick.lowercased() else { return }
            isOperator = true

        case "317": // RPL_WHOISIDLE  nick idlesecs signontime :idle message
            guard msg.parameters.count >= 3 else { return }
            guard msg.parameters[1].lowercased() == targetNick.lowercased() else { return }
            idleSecs = Int(msg.parameters[2])

        case "319": // RPL_WHOISCHANNELS  nick :channels
            guard msg.parameters.count >= 3 else { return }
            guard msg.parameters[1].lowercased() == targetNick.lowercased() else { return }
            channels = (msg.parameters.last ?? "").split(separator: " ").map(String.init)

        case "330": // RPL_WHOISACCOUNT  nick account :is logged in as
            guard msg.parameters.count >= 3 else { return }
            guard msg.parameters[1].lowercased() == targetNick.lowercased() else { return }
            account = msg.parameters[2]

        case "671": // RPL_WHOISSECURE
            guard msg.parameters.count >= 2 else { return }
            guard msg.parameters[1].lowercased() == targetNick.lowercased() else { return }
            isSecure = true

        case "318": // RPL_ENDOFWHOIS
            isLoadingWhois = false
            whoisDone = true

        default:
            break
        }
    }

    private func deregisterWhoisCallback() {
        // Restore the previous handler rather than setting nil,
        // so ChatView's topic feed (numeric 332) continues working.
        ircManager.getClient(for: serverId)?.onUnhandledMessage = _savedUnhandledHandler
    }

    // MARK: - Helpers

    private func formatIdle(_ seconds: Int) -> String {
        if seconds < 60   { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return "\(h)h \(m)m"
    }
}

#Preview {
    UserProfileSheet(
        nick: "alice",
        member: ChannelMember(nick: "alice", username: "alice", hostname: "example.com",
                              mode: .operator_, isAway: false),
        serverId: "preview"
    )
    .environmentObject(IRCClientManager.shared)
}
