import SwiftUI

struct ServerSelectionView: View {
    @EnvironmentObject var ircManager: IRCClientManager
    @EnvironmentObject var appState: AppState
    
    @State private var connectingServer: Server?
    @State private var connectingChannel: Channel?
    @State private var showError = false
    @State private var errorMessage = ""
    
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
                                        
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $connectingServer) { server in
                if let channel = connectingChannel {
                    TerminalView(server: server, channel: channel, startConnecting: true)
                        .environmentObject(ircManager)
                        .environmentObject(appState)
                }
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func connect(to server: (name: String, host: String, port: Int, channels: [String])) {
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
        
        connectingServer = serverConfig
        connectingChannel = Channel(name: serverConfig.lastActiveChannel ?? "#linux")
        print("[ServerSelection] set connectingServer = \(serverConfig.name)")
    }
}

#Preview {
    ServerSelectionView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
}