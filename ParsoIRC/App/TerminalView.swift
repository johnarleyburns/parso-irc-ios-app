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
            
            // ALWAYS visible - just show state
            VStack {
                Text("startConnecting: \(startConnecting ? "YES" : "NO")")
                    .foregroundColor(.yellow)
                Text("showConnecting: \(showConnecting ? "YES" : "NO")")
                    .foregroundColor(.orange)
                Text("isConnected: \(isConnected ? "YES" : "NO")")
                    .foregroundColor(.red)
            }
            
            // Always layered on top
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
            guard startConnecting else { return }
            await showConnectingState()
        }
    }
    
    private func showConnectingState() async {
        print("[TerminalView] showConnectingState BEGINS")
        print("[TerminalView] server: \(server.host):\(server.port), ssl: \(server.ssl)")
        
        let nickname = server.nickname.isEmpty ? "parso\(Int.random(in: 1000...9999))" : server.nickname
        let username = server.realname.isEmpty ? "parso" : server.realname
        let realname = server.realname.isEmpty ? "Parso IRC" : server.realname
        
        print("[TerminalView] Creating IRCClient for \(nickname)...")
        ircClient = IRCClient()
        
        guard let client = ircClient else {
            print("[TerminalView] ERROR: Failed to create IRCClient")
            return
        }
        print("[TerminalView] IRCClient created, calling connect()...")
        
        client.onDisconnect = {
            Task { @MainActor in
                print("[TerminalView] onDisconnect fired")
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
            print("[TerminalView] connect() succeeded!")
            
            await MainActor.run {
                print("[TerminalView] Setting isConnected = true, showConnecting = false")
                self.isConnected = true
                self.showConnecting = false
                print("[TerminalView] State updated")
            }
        } catch {
            print("[TerminalView] connect() FAILED: \(error)")
            await MainActor.run {
                self.isConnected = false
            }
        }
        
        print("[TerminalView] showConnectingState ENDS")
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