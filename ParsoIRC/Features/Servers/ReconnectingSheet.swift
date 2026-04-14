import SwiftUI

struct ReconnectingSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    let serverId: String
    let channelName: String
    
    @State private var isConnecting = true
    @State private var connectionError: String?
    @State private var connectionTimeout = false
    @State private var retryCount = 0
    
    @State private var connectionTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color.theme.sentBubble)
                
                VStack(spacing: 8) {
                    Text("Reconnecting to \(serverName)...")
                        .font(.headline)
                    
                    if connectionTimeout {
                        Text("Taking longer than expected...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if retryCount > 0 {
                        Text("Attempt \(retryCount + 1)...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = connectionError {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        HStack(spacing: 16) {
                            Button("Cancel") {
                                connectionTask?.cancel()
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Try Again") {
                                connectionError = nil
                                connectionTimeout = false
                                retryCount += 1
                                initiateConnection()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Reconnecting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        connectionTask?.cancel()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(isConnecting)
            .onAppear {
                initiateConnection()
            }
        }
    }
    
    private var serverName: String {
        appState.servers.first(where: { $0.id == serverId })?.name ?? "Server"
    }
    
    private var server: Server? {
        appState.servers.first(where: { $0.id == serverId })
    }
    
    private func initiateConnection() {
        guard let server = server else {
            connectionError = "Server not found"
            return
        }
        
        isConnecting = true
        connectionError = nil
        
        var serverToConnect = server
        if let lastChannel = server.lastActiveChannel, !lastChannel.isEmpty {
            // Use last active channel - already set
        } else if let firstChannel = server.channels.first {
            serverToConnect.lastActiveChannel = firstChannel.name
        }
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    connectionTimeout = true
                }
            }
        }
        
        connectionTask = Task {
            do {
                try await ircManager.connectWithHistory(to: serverToConnect) { serverId, channelName in
                    timeoutTask.cancel()
                    Task { @MainActor in
                        appState.navigateToChannel(serverId: serverId, channelName: channelName)
                        isConnecting = false
                        dismiss()
                    }
                }
            } catch {
                timeoutTask.cancel()
                await MainActor.run {
                    isConnecting = false
                    connectionError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ReconnectingSheet(serverId: "test", channelName: "#libera")
        .environmentObject(AppState())
        .environmentObject(IRCClientManager.shared)
}
