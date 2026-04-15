import SwiftUI

class DebugMessages: ObservableObject {
    static let shared = DebugMessages()
    
    @Published var messages: [String] = []
    @Published var isExpanded = false
    
    private let maxMessages = 50
    
    func addMessage(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let formatted = "[\(timestamp)] \(message)"
        
        DispatchQueue.main.async {
            self.messages.append(formatted)
            if self.messages.count > self.maxMessages {
                self.messages.removeFirst()
            }
        }
    }
    
    func clear() {
        messages.removeAll()
    }
}

struct DebugToastView: View {
    @ObservedObject var debugMessages = DebugMessages.shared
    
    var body: some View {
        VStack {
            Spacer()
            
            if debugMessages.isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Debug Log")
                            .font(.caption)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button("Clear") {
                            debugMessages.clear()
                        }
                        .font(.caption)
                        
                        Button(debugMessages.isExpanded ? "▼" : "▲") {
                            withAnimation {
                                debugMessages.isExpanded.toggle()
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.8))
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(debugMessages.messages, id: \.self) { msg in
                                Text(msg)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 300)
                    .background(Color.black.opacity(0.8))
                }
                .cornerRadius(8)
                .padding()
            } else {
                HStack {
                    Spacer()
                    Button {
                        withAnimation {
                            debugMessages.isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Debug (\(debugMessages.messages.count))")
                        }
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding()
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        DebugToastView()
    }
}
