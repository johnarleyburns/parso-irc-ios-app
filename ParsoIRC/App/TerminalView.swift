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
        VStack {
            Text("HELLO WORLD")
                .font(.largeTitle)
                .foregroundColor(.red)
            
            Button("TEST BUTTON") {
                print("Button tapped")
            }
            
            if startConnecting {
                Text("Connecting: YES")
            } else {
                Text("Connecting: NO")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue)
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