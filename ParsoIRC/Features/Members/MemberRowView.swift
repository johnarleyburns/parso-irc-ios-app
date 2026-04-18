import SwiftUI

/// A single row in the member list.
///
/// Shows:
/// - `AvatarView` with the nick's deterministic color
/// - Mode prefix badge (operator @, voiced +, halfop %, admin &, founder ~)
/// - Nick colored by `NickColorGenerator`
/// - Away indicator (muted orange dot)
/// - Optional username@host in secondary label
struct MemberRowView: View {
    let member: ChannelMember

    /// Called when the row is tapped.
    var onTap: ((ChannelMember) -> Void)? = nil

    var body: some View {
        Button {
            onTap?(member)
        } label: {
            HStack(spacing: 12) {
                // Avatar with away overlay
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(nick: member.nick, size: 40, showBorder: false)
                    if member.isAway {
                        Circle()
                            .fill(Color(.systemOrange))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    }
                }

                // Nick + host
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // Mode badge
                        if member.mode != .none {
                            Text(member.mode.displayName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(modeColor(member.mode))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(modeColor(member.mode).opacity(0.15))
                                )
                        }
                        Text(member.nick)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(NickColorGenerator.color(for: member.nick))
                    }

                    if let user = member.username, let host = member.hostname {
                        Text("\(user)@\(host)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let user = member.username {
                        Text(user)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    // MARK: - Mode color

    static func modeColor(_ mode: ChannelMember.MemberMode) -> Color {
        switch mode {
        case .founder:   return Color(.systemYellow)
        case .admin:     return Color(.systemOrange)
        case .operator_: return Color(.systemGreen)
        case .halfop:    return Color(.systemTeal)
        case .voice:     return Color(.systemBlue)
        case .none:      return Color(.secondaryLabel)
        }
    }

    private func modeColor(_ mode: ChannelMember.MemberMode) -> Color {
        MemberRowView.modeColor(mode)
    }
}

#Preview {
    List {
        MemberRowView(member: ChannelMember(nick: "founder",  mode: .founder,   isAway: false))
        MemberRowView(member: ChannelMember(nick: "admin",    mode: .admin,     isAway: false))
        MemberRowView(member: ChannelMember(nick: "operator", mode: .operator_, isAway: false))
        MemberRowView(member: ChannelMember(nick: "halfop",   mode: .halfop,    isAway: true))
        MemberRowView(member: ChannelMember(nick: "voiced",   mode: .voice,     isAway: false))
        MemberRowView(member: ChannelMember(nick: "plainuser", username: "user", hostname: "host.example.com",
                                            mode: .none, isAway: false))
    }
}
