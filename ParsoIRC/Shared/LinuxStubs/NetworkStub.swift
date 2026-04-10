// Stub for Network framework (Linux)
#if canImport(Network)
#else
import Foundation

public class NWConnection {
    public enum State {
        case setup
        case waiting
        case preparing
        case ready
        case failed(NWError?)
        case cancelled
    }
    public typealias StateUpdateHandler = (State) -> Void
    public init() {}
    public init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) {}
    public init(host: String, port: UInt16, using: NWParameters) {}
    public func start(queue: DispatchQueue) {}
    public func cancel() {}
    public var state: State = .setup
    public var stateUpdateHandler: StateUpdateHandler?

    public enum SendCompletion {
        case contentProcessed((NWError?) -> Void)
        case id
    }

    public func send(content: Data?, completion: SendCompletion) {}
    public func send(content: Data?, completion: @escaping (NWError?) -> Void) {}

    public func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping (Data?, NWError?, Bool, Swift.Error?) -> Void) {}
}
public struct NWEndpoint {
    public struct Host: ExpressibleByStringLiteral {
        public let rawValue: String
        public init(_ host: String) { self.rawValue = host }
        public init(stringLiteral: String) { self.rawValue = stringLiteral }
    }
    public struct Port: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
        public let rawValue: UInt16
        public static var http: Port { 80 }
        public static var https: Port { 443 }
        public init(integerLiteral: UInt16) { self.rawValue = integerLiteral }
        public init(_ rawValue: UInt16) { self.rawValue = rawValue }
        public init(stringLiteral: String) { self.rawValue = UInt16(stringLiteral) ?? 0 }
    }
}
public class NWListener {
    public enum State {
        case setup
        case waiting
        case ready
        case failed(NWError?)
        case cancelled
    }
    public var state: State = .setup
    public init() {}
    public init(using: NWParameters) {}
    public func start(queue: DispatchQueue) {}
    public func cancel() {}
    public func newConnection() -> NWConnection? { nil }
}
public struct NWParameters {
    public static var tcp: NWParameters { NWParameters() }
    public init() {}
    public init(tls: TLSOptions?) {}
    public struct TLSOptions {
        public init() {}
    }
}
public struct NWError: Error, Equatable {
    public let code: Code
    public enum Code: Equatable {
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
    public var localizedDescription: String { "" }
}
#endif