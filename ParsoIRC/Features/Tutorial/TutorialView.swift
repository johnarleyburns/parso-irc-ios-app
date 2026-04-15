import SwiftUI

struct TutorialView: View {
    @ObservedObject var tutorialManager = TutorialManager.shared
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    @State private var messageText = ""
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        Button {
                            tutorialManager.skip()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    Text(tutorialManager.currentStep.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(tutorialManager.currentStep.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(Color.theme.sentBubble.opacity(0.9))
                .cornerRadius(16)
                .padding()
                
                Spacer()
                
                VStack(spacing: 16) {
                    switch tutorialManager.currentStep {
                    case .welcome:
                        Button {
                            startTutorial()
                        } label: {
                            Text("Start Tutorial")
                                .font(.headline)
                                .foregroundColor(Color.theme.sentBubble)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        
                    case .connecting:
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Connecting to Libera.Chat...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                    case .joiningChannel:
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Joining #linux...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                    case .sendMessage:
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Say hello!", text: $messageText)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.horizontal)
                                
                                Button {
                                    sendMessage()
                                } label: {
                                    Image(systemName: "paperplane.fill")
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.theme.sentBubble)
                                        .cornerRadius(8)
                                }
                                .disabled(messageText.isEmpty)
                            }
                            .padding(.horizontal)
                        }
                        
                    case .complete:
                        Button {
                            tutorialManager.complete()
                        } label: {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundColor(Color.theme.sentBubble)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    private func startTutorial() {
        Task {
            tutorialManager.updateConnectionStatus(.connecting)
            
            let libera = Server.defaultNetworks.first { $0.name == "Libera.Chat" }!
            
            do {
                try await ircManager.connect(to: libera)
                tutorialManager.updateConnectionStatus(.connected)
                
                try await Task.sleep(nanoseconds: 500_000_000)
                
                if let client = ircManager.getClient(for: libera.id) {
                    try await client.join(channel: "#linux")
                    tutorialManager.nextStep()
                }
            } catch {
                tutorialManager.updateConnectionStatus(.failed(error))
            }
        }
        
        tutorialManager.nextStep()
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        Task {
            if let server = appState.servers.first(where: { $0.name == "Libera.Chat" }),
               let client = ircManager.getClient(for: server.id) {
                try? await client.send(message: messageText, to: "#linux")
            }
        }
        
        messageText = ""
        tutorialManager.nextStep()
    }
}

#Preview {
    TutorialView()
        .environmentObject(AppState())
        .environmentObject(IRCClientManager.shared)
}
