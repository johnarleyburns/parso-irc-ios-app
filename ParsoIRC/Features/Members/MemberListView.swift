import SwiftUI

/// Full member list for a channel, grouped by privilege level.
///
/// Receives the live `ChannelViewModel` as an `@ObservedObject` so the list
/// updates reactively as NAMES / JOIN / PART / QUIT events arrive — even if
/// the sheet was opened before the NAMES reply completed.
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
    /// Live channel view model — members update reactively.
    @ObservedObject var viewModel: ChannelViewModel
    let channelName: String
    let serverId: String

    /// Called when the user taps "Mention" in UserProfileSheet.
    var onMention: ((String) -> Void)? = nil
    /// Called when the user taps "Send Direct Message". Provides (nick, serverId).
    var onDM: ((String, String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedMember: ChannelMember? = nil

    // MARK: - Filtered + grouped

    private var filtered: [ChannelMember] {
        guard !searchText.isEmpty else { return viewModel.members }
        return viewModel.members.filter {
            $0.nick.localizedCaseInsensitiveContains(searchText)
        }
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
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
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
                },
                onBlock: { nick in
                    // Update the live ChannelViewModel so messages disappear
                    // immediately — without this the messages only hide on next launch.
                    viewModel.blockSender(nick: nick)
                    selectedMember = nil
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
        let total = viewModel.members.count
        switch total {
        case 0:  return channelName
        case 1:  return "\(channelName) — 1 member"
        default: return "\(channelName) — \(total) members"
        }
    }
}

#Preview {
    // Preview with a mock ChannelViewModel (can't init without real manager, so use a simple wrapper)
    struct PreviewWrapper: View {
        var body: some View {
            Text("MemberListView preview — use in-app for live data")
        }
    }
    return PreviewWrapper()
}
