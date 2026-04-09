import SwiftUI

struct MemberListView: View {
    let channel: Channel
    let server: Server
    
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var members: [ChannelMember] = []
    @State private var filterMode: MemberFilter = .all
    
    enum MemberFilter: String, CaseIterable {
        case all = "All"
        case ops = "Ops"
        case voice = "Voice"
    }
    
    var filteredMembers: [ChannelMember] {
        var result = members
        
        switch filterMode {
        case .all:
            break
        case .ops:
            result = result.filter { $0.mode == .operator_ || $0.mode == .admin || $0.mode == .founder }
        case .voice:
            result = result.filter { $0.mode == .voice }
        }
        
        if !searchText.isEmpty {
            result = result.filter { $0.nick.localizedCaseInsensitiveContains(searchText) }
        }
        
        return result.sorted { $0.mode.rawValue > $1.mode.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filterMode) {
                    ForEach(MemberFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                List(filteredMembers) { member in
                    MemberCell(member: member)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search members")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadMembers()
            }
        }
    }
    
    private func loadMembers() {
        // In a real app, this would fetch from the IRC client
        // For now, use sample data
        members = [
            ChannelMember(nick: "channel-operator", mode: .operator_),
            ChannelMember(nick: "voice-user", mode: .voice),
            ChannelMember(nick: "regular-user", mode: .none),
            ChannelMember(nick: "another-user", mode: .none),
            ChannelMember(nick: "away-user", mode: .none, isAway: true),
        ]
    }
}

struct MemberCell: View {
    let member: ChannelMember
    
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(nick: member.nick, size: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if !member.mode.displayName.isEmpty {
                        Text(member.mode.displayName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(modeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Text(member.nick)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if member.isAway {
                        Text("(Away)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let hostname = member.hostname {
                    Text(hostname)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Menu {
                Button {
                    // Send message
                } label: {
                    Label("Message", systemImage: "message")
                }
                
                Button {
                    // Whois
                } label: {
                    Label("Whois", systemImage: "person.magnifyingglass")
                }
                
                Button {
                    // Ignore
                } label: {
                    Label("Ignore", systemImage: "bell.slash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var modeColor: Color {
        switch member.mode {
        case .operator_, .admin, .founder:
            return .red
        case .voice:
            return .green
        case .none:
            return .gray
        }
    }
}

#Preview {
    MemberListView(channel: Channel(name: "#libera"), server: Server.defaultNetworks[0])
}