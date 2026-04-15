import Foundation

enum TutorialStep: Int, CaseIterable {
    case welcome = 0
    case connecting
    case joiningChannel
    case sendMessage
    case complete
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .connecting: return "Connecting"
        case .joiningChannel: return "Join Channel"
        case .sendMessage: return "Send Message"
        case .complete: return "Complete"
        }
    }
    
    var description: String {
        switch self {
        case .welcome:
            return "Let's get you connected to IRC! This tutorial will guide you through joining the #linux channel on Libera.Chat."
        case .connecting:
            return "Connecting to Libera.Chat server..."
        case .joiningChannel:
            return "Joining the #linux channel..."
        case .sendMessage:
            return "Type a message in the chat box to say hello!"
        case .complete:
            return "You're all set! Enjoy chatting on IRC."
        }
    }
}

@MainActor
class TutorialManager: ObservableObject {
    static let shared = TutorialManager()
    
    @Published var currentStep: TutorialStep = .welcome
    @Published var isActive = false
    @Published var isComplete = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }
    
    private init() {}
    
    func start() {
        currentStep = .welcome
        isActive = true
        isComplete = false
    }
    
    func nextStep() {
        guard let next = TutorialStep(rawValue: currentStep.rawValue + 1) else {
            complete()
            return
        }
        currentStep = next
    }
    
    func complete() {
        currentStep = .complete
        isComplete = true
        isActive = false
    }
    
    func skip() {
        isActive = false
    }
    
    func updateConnectionStatus(_ status: ConnectionStatus) {
        connectionStatus = status
        
        if case .connected = status {
            if currentStep == .connecting {
                nextStep()
            }
        }
    }
}
