// Stub for UIKit (Linux only)
#if os(Linux)
import Foundation
public class UIColor: NSObject {}
public struct CGRect: Hashable {
    public static var zero: CGRect { CGRect(x: 0, y: 0, width: 0, height: 0) }
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init() {}
}
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
    public var rootViewController: UIViewController? { get { nil } set { } }
    public func makeKeyAndVisible() {}
}
public class UIViewController: NSObject {}
public class UIView: NSObject {
    public override init() {}
    public var frame: CGRect { get { .zero } set { } }
    public var backgroundColor: UIColor? { get { nil } set { } }
}
public class NSObject: @unchecked Sendable {}
public struct Notification {
    public struct Name: Hashable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}
#endif