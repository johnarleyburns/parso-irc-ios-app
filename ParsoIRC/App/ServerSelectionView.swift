import SwiftUI

struct ServerSelectionView: View {
    @EnvironmentObject var ircManager: IRCClientManager
    @EnvironmentObject var appState: AppState
    
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTerminal = false
    
    private let servers: [(name: String, host: String, port: Int, channels: [String])] = [
        ("Libera.Chat", "irc.libera.chat", 6697, ["#linux", "#kde", "#libera", "#archlinux"]),
        ("OFTC", "irc.oftc.org", 6697, ["#linux", "#debian", "#ubuntu"]),
        ("Hackint", "irc.hackint.org", 6697, ["#linux", "#hackint"])
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Text("Select IRC Server")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding(.top, 60)
                        .padding(.bottom, 30)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(servers, id: \.name) { server in
                                Button {
                                    connect(to: server)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(server.name)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            
                                            Text("\(server.host):\(server.port)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            
                                            Text(server.channels.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        if isConnecting {
                                            ProgressView()
                                                .tint(.green)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(12)
                                }
                                .disabled(isConnecting)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private func connect(to server: (name: String, host: String, port: Int, channels: [String])) {
        isConnecting = true
        
        let serverConfig = Server(
            id: UUID().uuidString,
            name: server.name,
            host: server.host,
            port: server.port,
            ssl: true,
            nickname: "parso\(Int.random(in: 1000...9999))",
            realname: "parso",
            password: nil,
            saslEnabled: false,
            autoConnect: false,
            channels: server.channels.map { Channel(name: $0) },
            lastActiveChannel: server.channels.first ?? "#linux"
        )
        
        Task {
            do {
                try await ircManager.connectWithHistory(to: serverConfig) { serverId, channelName in
                    await MainActor.run {
                        showTerminal = true
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isConnecting = false
                }
            }
        }
    }
}

#Preview {
    ServerSelectionView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
}