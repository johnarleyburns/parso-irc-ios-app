// Stub for Network framework (Linux)
#if canImport(Network)
#else
import Foundation
public enum NWConnection {
    public enum State {
        case setup
        case waiting
        case preparing
        case ready
        case failed
        case cancelled
    }
    public typealias StateUpdateHandler = (State) -> Void
    public init() {}
    public init(host: String, port: UInt16, using: NWParameters) {}
    public func start(queue: DispatchQueue) {}
    public func cancel() {}
    public var state: State = .setup
    public var stateUpdateHandler: StateUpdateHandler?
    public func send(content: Data?, completion: @escaping (NWError?) -> Void) {}
    public func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping (Data?, NWError?) -> Void) {}
}
public struct NWEndpoint {
    public struct Host {
        public let rawValue: String
        public init(_ host: String) { self.rawValue = host }
    }
    public struct Port {
        public let rawValue: UInt16
        public static var http: Port { Port(rawValue: 80) }
        public static var https: Port { Port(rawValue: 443) }
        public init(integerLiteral: UInt16) { self.rawValue = integerLiteral }
    }
}
public struct NWParameters {
    public static var tcp: NWParameters { NWParameters() }
    public init() {}
    public init(tls: TLSOptions?) {}
    public struct TLSOptions {
        public init() {}
    }
}
public struct NWError: Error {
    public let code: Code
    public enum Code {
        case invalidParameter
        case dnsLookupFailed
        case connectionFailed
        case connectionReset
        case connectionClosed
        case notConnected
        case invalidMessage
        case peerGoneAway
        case cancelled
    }
    public init(_ code: Code) { self.code = code }
}
#endif