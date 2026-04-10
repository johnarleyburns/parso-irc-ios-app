import Foundation

enum IRCError: LocalizedError {
    case notConnected
    case maxReconnectAttemptsReached
    case authenticationFailed
    case connectionFailed(String)
    case invalidResponse(String)
    case sendFailed(String)
    case timeout
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .maxReconnectAttemptsReached:
            return "Maximum reconnection attempts reached"
        case .authenticationFailed:
            return "Authentication failed"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .sendFailed(let message):
            return "Failed to send: \(message)"
        case .timeout:
            return "Connection timeout"
        case .encodingFailed:
            return "Failed to encode message"
        }
    }
}

enum IRCConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(IRCError)
}