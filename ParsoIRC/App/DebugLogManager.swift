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

final class DebugLogManager: ObservableObject, @unchecked Sendable {
    static let shared = DebugLogManager()
    
    @Published var logs: [DebugLogEntry] = []
    
    private let maxLogs = 500
    private let queue = DispatchQueue(label: "debuglog", qos: .userInteractive)
    
    private init() {}
    
    func log(_ message: String, type: DebugLogEntry.LogType = .info) {
        let entry = DebugLogEntry(id: UUID(), timestamp: Date(), message: message, type: type)
        
        queue.async { [weak self] in
            guard let self = self else { return }
            var updatedLogs = self.logs
            updatedLogs.append(entry)
            if updatedLogs.count > self.maxLogs {
                updatedLogs.removeFirst(updatedLogs.count - self.maxLogs)
            }
            DispatchQueue.main.async {
                self.logs = updatedLogs
            }
        }
    }
    
    func clear() {
        queue.async { [weak self] in
            DispatchQueue.main.async {
                self?.logs.removeAll()
            }
        }
    }
}