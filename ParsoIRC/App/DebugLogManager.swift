import Foundation

struct DebugLogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let message: String
    let type: LogType
    
    enum LogType: String, Sendable {
        case info = "INFO"
        case sent = "SENT"
        case received = "RECV"
        case error = "ERROR"
    }
}

@MainActor
final class DebugLogManager: ObservableObject {
    static let shared = DebugLogManager()
    
    @Published var logs: [DebugLogEntry] = []
    
    private let maxLogs = 500
    
    private init() {}
    
    nonisolated func log(_ message: String, type: DebugLogEntry.LogType = .info) {
        let entry = DebugLogEntry(id: UUID(), timestamp: Date(), message: message, type: type)
        
        Task { @MainActor in
            self.logs.append(entry)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
    }
    
    nonisolated func clear() {
        Task { @MainActor in
            self.logs.removeAll()
        }
    }
}