import SwiftUI

/// Full member list for a channel, grouped by privilege level.
///
/// Sections (only shown when non-empty):
///   Founders & Admins  (~, &)
///   Operators          (@)
///   Half-ops           (%)
///   Voiced             (+)
///   Members            (no prefix)
///
/// A search bar filters across all sections simultaneously.
/// Tapping a row opens `UserProfileSheet` for that nick.
struct MemberListView: View {
    /// All members for this channel (already sorted by ChannelViewModel).
    let members: [ChannelMember]
    let channelName: String
    let serverId: String

    /// Called when the user taps "Mention" in UserProfileSheet or taps a nick directly.
    var onMention: ((String) -> Void)? = nil
    /// Called when the user taps "Send Direct Message". Provides (nick, serverId).
    var onDM: ((String, String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedMember: ChannelMember? = nil

    // MARK: - Filtered + grouped

    private var filtered: [ChannelMember] {
        guard !searchText.isEmpty else { return members }
        return members.filter { $0.nick.localizedCaseInsensitiveContains(searchText) }
    }

    private var founders:  [ChannelMember] { filtered.filter { $0.mode == .founder || $0.mode == .admin } }
    private var operators: [ChannelMember] { filtered.filter { $0.mode == .operator_ } }
    private var halfops:   [ChannelMember] { filtered.filter { $0.mode == .halfop } }
    private var voiced:    [ChannelMember] { filtered.filter { $0.mode == .voice } }
    private var regulars:  [ChannelMember] { filtered.filter { $0.mode == .none } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                memberSection(title: "Founders & Admins",
                              icon: "star.fill",
                              iconColor: .yellow,
                              members: founders)

                memberSection(title: "Operators",
                              icon: "person.badge.shield.checkmark",
                              iconColor: .green,
                              members: operators)

                memberSection(title: "Half-ops",
                              icon: "person.fill.checkmark",
                              iconColor: Color(.systemTeal),
                              members: halfops)

                memberSection(title: "Voiced",
                              icon: "mic.fill",
                              iconColor: .blue,
                              members: voiced)

                memberSection(title: "Members",
                              icon: "person.fill",
                              iconColor: .secondary,
                              members: regulars)
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search members")
            .navigationTitle(memberCountTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedMember) { member in
            UserProfileSheet(
                nick: member.nick,
                member: member,
                serverId: serverId,
                onMention: { nick in
                    selectedMember = nil
                    dismiss()
                    onMention?(nick)
                },
                onDM: { nick, sid in
                    selectedMember = nil
                    dismiss()
                    onDM?(nick, sid)
                }
            )
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func memberSection(
        title: String,
        icon: String,
        iconColor: Color,
        members: [ChannelMember]
    ) -> some View {
        if !members.isEmpty {
            Section {
                ForEach(members) { member in
                    MemberRowView(member: member) { tapped in
                        selectedMember = tapped
                    }
                }
            } header: {
                Label(title, systemImage: icon)
                    .foregroundStyle(iconColor)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Helpers

    private var memberCountTitle: String {
        let total = members.count
        switch total {
        case 0:  return channelName
        case 1:  return "\(channelName) — 1 member"
        default: return "\(channelName) — \(total) members"
        }
    }
}

#Preview {
    MemberListView(
        members: [
            ChannelMember(nick: "alice",   mode: .founder),
            ChannelMember(nick: "bob",     mode: .operator_),
            ChannelMember(nick: "charlie", mode: .halfop,    isAway: true),
            ChannelMember(nick: "dave",    mode: .voice),
            ChannelMember(nick: "eve",     username: "eve", hostname: "example.com", mode: .none),
            ChannelMember(nick: "frank",   mode: .none,     isAway: true),
        ],
        channelName: "#linux",
        serverId: "preview"
    )
}
