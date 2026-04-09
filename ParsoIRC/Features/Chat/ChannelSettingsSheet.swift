import SwiftUI

struct ChannelSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var watchManager: WatchManager
    
    let channel: Channel
    let server: Server
    @Binding var updatedChannel: Channel
    
    @State private var isWatched: Bool
    @State private var notifyOnAnyMessage: Bool
    
    init(channel: Channel, server: Server, updatedChannel: Binding<Channel>) {
        self.channel = channel
        self.server = server
        self._updatedChannel = updatedChannel
        self._isWatched = State(initialValue: channel.isWatched)
        self._notifyOnAnyMessage = State(initialValue: channel.notifyOnAnyMessage)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.theme.sentBubble.opacity(0.2))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "number")
                                .font(.title2)
                                .foregroundColor(Color.theme.sentBubble)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name)
                                .font(.headline)
                            
                            Text(server.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    Toggle(isOn: $isWatched) {
                        HStack(spacing: 12) {
                            Image(systemName: isWatched ? "eye.fill" : "eye")
                                .foregroundColor(isWatched ? Color.theme.sentBubble : .secondary)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Watch Channel")
                                    .font(.body)
                                
                                Text("Get notified about activity")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(Color.theme.sentBubble)
                    .onChange(of: isWatched) { _, newValue in
                        updatedChannel.isWatched = newValue
                        HapticManager.lightImpact()
                        
                        if newValue {
                            watchManager.scheduleBackgroundTask()
                        }
                    }
                } footer: {
                    Text("Watched channels are monitored in the background for new messages.")
                }
                
                if isWatched {
                    Section("Notification Type") {
                        Picker("Notify me about", selection: $notifyOnAnyMessage) {
                            Text("Mentions only").tag(false)
                            Text("All messages").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: notifyOnAnyMessage) { _, newValue in
                            updatedChannel.notifyOnAnyMessage = newValue
                        }
                    } footer: {
                        Text(notifyOnAnyMessage ? "You'll be notified about every message." : "You'll only be notified when someone mentions your nickname.")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        // Leave channel action - would need callback
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.left.circle")
                            Text("Leave Channel")
                        }
                    }
                }
            }
            .navigationTitle("Channel Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func saveChanges() {
        Task {
            // Save to database
            do {
                try DatabaseManager.shared.saveChannel(updatedChannel, serverId: server.id)
            } catch {
                print("Failed to save channel settings: \(error)")
            }
        }
    }
}

#Preview {
    ChannelSettingsSheet(
        channel: Channel(name: "#libera", isWatched: false),
        server: Server.defaultNetworks[0],
        updatedChannel: .constant(Channel(name: "#libera"))
    )
    .environmentObject(WatchManager.shared)
}