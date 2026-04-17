import Foundation

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType
    
    enum LogType: String {
        case info = "INFO"
        case sent = "SENT"
        case received = "RECV"
        case error = "ERROR"
    }
}

@MainActor
class DebugLogManager: ObservableObject {
    static let shared = DebugLogManager()
    
    @Published var logs: [DebugLogEntry] = []
    
    private let maxLogs = 500
    
    private init() {}
    
    nonisolated func log(_ message: String, type: DebugLogEntry.LogType = .info) {
        Task { @MainActor in
            let entry = DebugLogEntry(timestamp: Date(), message: message, type: type)
            self.logs.append(entry)
            
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
    }
    
    func clear() {
        logs.removeAll()
    }
}