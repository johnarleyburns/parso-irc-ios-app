import SwiftUI

struct AddServerSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "6697"
    @State private var ssl: Bool = true
    @State private var nickname: String = ""
    @State private var realname: String = ""
    @State private var password: String = ""
    @State private var saslEnabled: Bool = false
    @State private var autoConnect: Bool = true
    @State private var selectedChannels: [String] = []
    
    let server: Server?
    
    init(server: Server? = nil) {
        self.server = server
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server Name", text: $name)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    
                    Toggle("SSL/TLS", isOn: $ssl)
                }
                
                Section("Identity") {
                    TextField("Nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("Real Name (optional)", text: $realname)
                    
                    SecureField("Server Password (optional)", text: $password)
                }
                
                Section("Authentication") {
                    Toggle("SASL Authentication", isOn: $saslEnabled)
                    
                    if saslEnabled {
                        TextField("SASL Password", text: $password)
                            .textInputAutocapitalization(.never)
                    }
                }
                
                Section("Channels") {
                    TextField("Add Channel", text: Binding(
                        get: { selectedChannels.last ?? "" },
                        set: { newValue in
                            if !newValue.isEmpty && newValue.hasPrefix("#") {
                                if !selectedChannels.contains(newValue) {
                                    selectedChannels.append(newValue)
                                }
                            }
                        }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        addChannel()
                    }
                    
                    ForEach(selectedChannels, id: \.self) { channel in
                        HStack {
                            Text(channel)
                            Spacer()
                            Button {
                                selectedChannels.removeAll { $0 == channel }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Auto-connect on launch", isOn: $autoConnect)
                }
                
                Section("Quick Add Network") {
                    Button("Libera.Chat") {
                        populateTemplate(
                            name: "Libera.Chat",
                            host: "irc.libera.chat",
                            port: "6697",
                            ssl: true,
                            channels: ["#libera", "#linux", "#bash", "#systemd", "#kernel"]
                        )
                    }
                    
                    Button("OFTC") {
                        populateTemplate(
                            name: "OFTC",
                            host: "irc.oftc.net",
                            port: "6697",
                            ssl: true,
                            channels: ["#debian", "#linux"]
                        )
                    }
                    
                    Button("hackint") {
                        populateTemplate(
                            name: "hackint",
                            host: "irc.hackint.org",
                            port: "6697",
                            ssl: true,
                            channels: []
                        )
                    }
                    
                    Button("Rizon") {
                        populateTemplate(
                            name: "Rizon",
                            host: "irc.rizon.net",
                            port: "6697",
                            ssl: true,
                            channels: []
                        )
                    }
                    
                    Button("Snoonet") {
                        populateTemplate(
                            name: "Snoonet",
                            host: "irc.snoonet.org",
                            port: "6697",
                            ssl: true,
                            channels: []
                        )
                    }
                }
            }
            .navigationTitle(server == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveServer()
                    }
                    .disabled(name.isEmpty || host.isEmpty)
                }
            }
            .onAppear {
                if let server = server {
                    name = server.name
                    host = server.host
                    port = String(server.port)
                    ssl = server.ssl
                    nickname = server.nickname
                    realname = server.realname
                    saslEnabled = server.saslEnabled
                    autoConnect = server.autoConnect
                    selectedChannels = server.channels.map { $0.name }
                }
            }
        }
    }
    
    private func addChannel() {
        let channel = selectedChannels.last ?? ""
        if !channel.isEmpty && channel.hasPrefix("#") && !selectedChannels.contains(channel) {
            selectedChannels.append(channel)
        }
    }
    
    private func populateTemplate(name: String, host: String, port: String, ssl: Bool, channels: [String]) {
        self.name = name
        self.host = host
        self.port = port
        self.ssl = ssl
        self.selectedChannels = channels
    }
    
    private func saveServer() {
        let channels = selectedChannels.map { Channel(name: $0) }
        
        let newServer = Server(
            id: server?.id ?? UUID().uuidString,
            name: name,
            host: host,
            port: Int(port) ?? 6697,
            ssl: ssl,
            nickname: nickname,
            realname: realname,
            password: password.isEmpty ? nil : password,
            saslEnabled: saslEnabled,
            autoConnect: autoConnect,
            channels: channels
        )
        
        Task {
            do {
                try DatabaseManager.shared.saveServer(newServer)
                await MainActor.run {
                    if let index = appState.servers.firstIndex(where: { $0.id == newServer.id }) {
                        appState.servers[index] = newServer
                    } else {
                        appState.servers.append(newServer)
                    }
                    dismiss()
                }
            } catch {
                print("Failed to save server: \(error)")
            }
        }
    }
}

#Preview {
    AddServerSheet()
        .environmentObject(AppState())
}