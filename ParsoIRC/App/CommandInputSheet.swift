import SwiftUI

struct CommandInputSheet: View {
    let commands: [(name: String, description: String)]
    let channel: Channel
    let server: Server
    let onSend: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var selectedCommand: String = "PRIVMSG"
    @State private var arguments: String = ""
    @State private var preview: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            
            // Command picker
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(commands, id: \.name) { cmd in
                        Button {
                            selectedCommand = cmd.name
                            updatePreview()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cmd.name)
                                        .font(.headline)
                                        .foregroundColor(selectedCommand == cmd.name ? .green : .white)
                                    Text(cmd.description)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                if selectedCommand == cmd.name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(selectedCommand == cmd.name ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            
            // Arguments input
            VStack(alignment: .leading, spacing: 8) {
                Text("Arguments")
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
                    .onChange(of: selectedCommand) { _, _ in
                        updatePreview()
                    }
            }
            .padding()
            
            // Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(preview.isEmpty ? "(enter arguments above)" : preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.1))
                    .cornerRadius(8)
            }
            .padding()
            
            // Send button
            Button {
                let args = formatArguments()
                onSend(selectedCommand, args)
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
    
    private func getPlaceholder() -> String {
        switch selectedCommand {
        case "NICK": return "newnick"
        case "USER": return "username realname"
        case "JOIN": return channel.name
        case "PART": return channel.name
        case "PRIVMSG": return "\(channel.name) message"
        case "ME": return "\(channel.name) action"
        case "WHOIS": return "nickname"
        case "AWAY": return "away message"
        case "QUIT": return "reason"
        default: return "arguments"
        }
    }
    
    private func formatArguments() -> String {
        switch selectedCommand {
        case "NICK": return arguments
        case "USER": return arguments
        case "JOIN": return arguments
        case "PART": return arguments.isEmpty ? channel.name : arguments
        case "PRIVMSG": return arguments
        case "ME": return arguments
        case "WHOIS": return arguments
        case "AWAY": return arguments
        case "QUIT": return arguments
        default: return arguments
        }
    }
    
    private func updatePreview() {
        let args = formatArguments()
        if args.isEmpty {
            preview = ":\(selectedCommand)"
        } else {
            preview = ":\(selectedCommand) \(args)"
        }
    }
    
    private var isValid: Bool {
        !arguments.isEmpty || selectedCommand == "QUIT"
    }
}

#Preview {
    CommandInputSheet(
        commands: [("NICK", "Set nickname"), ("JOIN", "Join channel"), ("PRIVMSG", "Send message")],
        channel: Channel(name: "#linux"),
        server: Server.defaultNetworks[0],
        onSend: { _, _ in },
        onCancel: { }
    )
}