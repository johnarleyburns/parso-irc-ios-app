import SwiftUI

struct CommandInputSheet: View {
    let channel: Channel
    let server: Server
    let onSend: (String, String) -> Void
    let onCancel: () -> Void
    
    private let commands: [(name: String, description: String, needsArgs: Bool)] = [
        ("NICK", "Set nickname", true),
        ("USER", "Set username", true),
        ("JOIN", "Join channel", true),
        ("PART", "Leave channel", true),
        ("LIST", "List channels", false),
        ("NAMES", "List users in channel", true),
        ("PRIVMSG", "Send private message", true),
        ("ME", "Action (/me)", true),
        ("WHOIS", "Query user", true),
        ("AWAY", "Set away status", false),
        ("QUIT", "Disconnect", false)
    ]
    
    @State private var selectedIndex: Int = 0
    @State private var arguments: String = ""
    @State private var preview: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Send IRC Command")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(.red)
            }
            .padding()
            .background(Color(white: 0.1))
            
            VStack(spacing: 16) {
                Text("Command")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Menu {
                    ForEach(0..<commands.count, id: \.self) { index in
                        Button {
                            selectedIndex = index
                            arguments = ""
                            updatePreview()
                        } label: {
                            HStack {
                                Text(commands[index].name)
                                Text(commands[index].description)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(commands[selectedIndex].name)
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(commands[selectedIndex].description)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            if commands[selectedIndex].needsArgs {
                VStack(alignment: .leading, spacing: 8) {
                    Text(getArgLabel())
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    TextField(getPlaceholder(), text: $arguments)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .onChange(of: arguments) { _, _ in
                            updatePreview()
                        }
                }
                .padding()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(preview.isEmpty ? "(no arguments needed)" : preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.1))
                    .cornerRadius(8)
            }
            .padding()
            
            Button {
                let args = formatArguments()
                onSend(commands[selectedIndex].name, args)
            } label: {
                Text("Send")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
            }
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.5)
            .padding()
        }
        .background(Color.black)
        .onAppear {
            updatePreview()
        }
    }
    
    private func getArgLabel() -> String {
        switch commands[selectedIndex].name {
        case "NICK": return "New Nickname"
        case "USER": return "Username Realname"
        case "JOIN": return "Channel (#channel)"
        case "PART": return "Channel (#channel)"
        case "NAMES": return "Channel (#channel)"
        case "PRIVMSG": return "Username Message"
        case "ME": return "Action Message"
        case "WHOIS": return "Username"
        case "AWAY": return "Away Message (optional)"
        case "QUIT": return "Reason (optional)"
        default: return "Arguments"
        }
    }
    
    private func getPlaceholder() -> String {
        switch commands[selectedIndex].name {
        case "NICK": return "newnick"
        case "USER": return "username realname"
        case "JOIN": return channel.name
        case "PART": return channel.name
        case "NAMES": return channel.name
        case "PRIVMSG": return "username message"
        case "ME": return "action message"
        case "WHOIS": return "username"
        case "AWAY": return "away message"
        case "QUIT": return "reason"
        default: return "arguments"
        }
    }
    
    private func formatArguments() -> String {
        let cmd = commands[selectedIndex].name
        if arguments.isEmpty {
            if cmd == "QUIT" { return "" }
            return ""
        }
        return arguments
    }
    
    private func updatePreview() {
        let cmd = commands[selectedIndex].name
        let args = arguments
        
        switch cmd {
        case "NICK":
            preview = args.isEmpty ? "NICK" : "NICK :\(args)"
        case "USER":
            preview = args.isEmpty ? "USER" : "USER \(args.replacingOccurrences(of: " ", with: " "))"
        case "JOIN":
            preview = args.isEmpty ? "JOIN \(channel.name)" : "JOIN \(args)"
        case "PART":
            preview = args.isEmpty ? "PART \(channel.name)" : "PART \(args)"
        case "LIST":
            preview = "LIST"
        case "NAMES":
            preview = args.isEmpty ? "NAMES \(channel.name)" : "NAMES \(args)"
        case "PRIVMSG":
            let parts = args.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let target = String(parts[0])
                let message = String(parts[1])
                preview = "PRIVMSG \(target) :\(message)"
            } else {
                preview = "PRIVMSG username :message"
            }
        case "ME":
            let action = "\u{0001}ACTION\u{0001}"
            preview = args.isEmpty ? "PRIVMSG \(channel.name) :\(action)" : "PRIVMSG \(channel.name) :\u{0001}ACTION \(args)\u{0001}"
        case "WHOIS":
            preview = args.isEmpty ? "WHOIS" : "WHOIS \(args)"
        case "AWAY":
            preview = args.isEmpty ? "AWAY" : "AWAY :\(args)"
        case "QUIT":
            preview = args.isEmpty ? "QUIT" : "QUIT :\(args)"
        default:
            preview = args.isEmpty ? cmd : "\(cmd) \(args)"
        }
    }
    
    private var isValid: Bool {
        let cmd = commands[selectedIndex].name
        if cmd == "QUIT" { return true }
        if commands[selectedIndex].needsArgs && arguments.isEmpty { return false }
        return true
    }
}

#Preview {
    CommandInputSheet(
        channel: Channel(name: "#linux"),
        server: Server.defaultNetworks[0],
        onSend: { _, _ in },
        onCancel: { }
    )
}