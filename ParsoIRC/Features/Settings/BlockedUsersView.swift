import SwiftUI

/// Settings sub-screen showing locally blocked users.
///
/// Swipe-to-unblock removes the nick from the DB and immediately
/// allows their messages to appear again.
struct BlockedUsersView: View {
    @State private var blockedNicks: [String] = []

    var body: some View {
        Group {
            if blockedNicks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(blockedNicks, id: \.self) { nick in
                        HStack(spacing: 12) {
                            AvatarView(nick: nick, size: 36, showBorder: false)
                            Text(nick)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: unblock)
                }
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !blockedNicks.isEmpty {
                EditButton()
            }
        }
        .onAppear(perform: loadBlockedUsers)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(Color(.systemGray3))
            Text("No Blocked Users")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("When you block someone, they'll appear here. Swipe to unblock.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func loadBlockedUsers() {
        blockedNicks = (try? DatabaseManager.shared.fetchBlockedUsers()) ?? []
    }

    private func unblock(at offsets: IndexSet) {
        let nicksToUnblock = offsets.map { blockedNicks[$0] }
        for nick in nicksToUnblock {
            try? DatabaseManager.shared.unblockUser(nick: nick)
        }
        blockedNicks.remove(atOffsets: offsets)
    }
}

#Preview {
    NavigationStack {
        BlockedUsersView()
    }
}
