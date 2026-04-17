import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var ircManager: IRCClientManager
    @EnvironmentObject var appState: AppState
    
    let server: Server
    let channel: Channel
    var startConnecting: Bool = false
    
    @State private var ircClient: IRCClient?
    @State private var isConnected = false
    @State private var showConnecting = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if showConnecting {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .green))
                        .scaleEffect(1.5)
                    Text("Connecting to \(server.host)...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 16)
                }
            } else if isConnected {
                VStack {
                    Text("CONNECTED")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text(server.host)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            if startConnecting {
                await showConnectingState()
            }
        }
    }
    
    private func showConnectingState() async {
        let nickname = server.nickname.isEmpty ? "parso\(Int.random(in: 1000...9999))" : server.nickname
        let username = server.realname.isEmpty ? "parso" : server.realname
        let realname = server.realname.isEmpty ? "Parso IRC" : server.realname
        
        ircClient = IRCClient()
        
        guard let client = ircClient else { return }
        
        client.onDisconnect = {
            Task { @MainActor in
                self.isConnected = false
                self.showConnecting = true
            }
        }
        
        do {
            try await client.connect(
                host: server.host,
                port: server.port,
                tls: server.ssl,
                nickname: nickname,
                username: username,
                realname: realname,
                serverPassword: server.password,
                useSASL: server.saslEnabled,
                saslPassword: server.password
            )
            
            await MainActor.run {
                self.isConnected = true
                self.showConnecting = false
            }
        } catch {
            await MainActor.run {
                self.isConnected = false
            }
        }
    }
}

#Preview {
    TerminalView(
        server: Server.defaultNetworks[0],
        channel: Channel(name: "#linux"),
        startConnecting: true
    )
    .environmentObject(IRCClientManager.shared)
    .environmentObject(AppState())
}