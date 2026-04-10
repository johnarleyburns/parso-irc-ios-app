// Stub for UIKit (Linux)
#if canImport(UIKit)
#else
import Foundation
public class UIColor: NSObject {}
public struct CGRect: Hashable {}
public struct CGSize: Hashable {}
public struct CGPoint: Hashable {}
public class UIFont: NSObject {}
public class UIImage: NSObject {}
public class UIApplication: NSObject {
    public static var shared: UIApplication { UIApplication() }
    public var keyWindow: UIWindow? { return nil }
    public var windows: [UIWindow] { return [] }
}
public class UIWindow: NSObject {
    public override init() {}
    public init(frame: CGRect) {}
    public var rootViewController: UIViewController? { get { nil } nonmutating set {} }
    public func makeKeyAndVisible() {}
}
public class UIViewController: NSObject {}
public class UIView: NSObject {
    public override init() {}
    public var frame: CGRect { get { .zero } nonmutating set {} }
    public var backgroundColor: UIColor? { get { nil } nonmutating set {} }
}
public class NSObject: @unchecked Sendable {}
public struct Notification {
    public struct Name: Hashable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}
#endif