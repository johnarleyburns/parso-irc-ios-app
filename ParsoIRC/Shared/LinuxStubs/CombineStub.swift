// Minimal Combine stub for type-checking only
#if canImport(Combine)
#else
import Foundation

public func pow(_ base: Double, _ exp: Double) -> Double {
    return Foundation.pow(base, exp)
}

public protocol ObservableObject: AnyObject {}
@propertyWrapper
public struct Published<Value> {
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public var wrappedValue: Value {
        get { fatalError("Published wrapper not implemented for Linux") }
        set { }
    }
    public var projectedValue: Published<Value> { self }
}

public class Cancellable {
    public init() {}
    public func cancel() {}
}
public class AnyCancellable: Cancellable {
    public override init() {}
    public override func cancel() {}
}
public struct PassthroughSubject<Output, Failure> {
    public init() {}
}
public struct CurrentValueSubject<Output, Failure> {
    public init(_ value: Output) {}
}
public struct Subscribers {
    public enum Completion<Failure> {}
}
public class AnyPublisher<Output, Failure: Error> {}

public protocol Publisher {
    associatedtype Output
    associatedtype Failure: Error
}
public protocol Subject: Publisher {
    func send(_ value: Output)
}
public protocol Subscriber {
    associatedtype Input
    associatedtype Failure: Error
}
public struct Subscription {
    public func cancel() {}
}

public class Timer {
    public static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        fatalError("Timer not implemented for Linux")
    }
    public func invalidate() {}
}

public class Server {
    public var id: String { "" }
    public var host: String { "" }
    public var port: Int = 6667
    public var ssl: Bool = false
    public var nickname: String { "" }
    public var realname: String { "" }
    public var saslEnabled: Bool = false
    public var password: String? { nil }
    public var channels: [Channel] { [] }
}

public class Channel {
    public var id: String { "" }
    public var serverId: String { "" }
    public var name: String { "" }
    public init() {}
}

public class Message {
    public var id: String { "" }
    public var channelId: String { "" }
    public var content: String { "" }
    public var timestamp: Date = Date()
    public var sender: String { "" }
    public init() {}
}

public class DatabaseManager {
    public static var shared: DatabaseManager { DatabaseManager() }
    public func fetchServers() throws -> [Server] { [] }
}
#endif