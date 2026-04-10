// Minimal Combine stub for type-checking only
#if canImport(Combine)
#else
import Foundation

public protocol ObservableObject: AnyObject {}
public struct Published<Value> {
    public init() {}
}
public final class Cancellable {
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
#endif