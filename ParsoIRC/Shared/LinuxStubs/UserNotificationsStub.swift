// Stub for UserNotifications (Linux)
#if canImport(UserNotifications)
#else
import Foundation
public class UNUserNotificationCenter {
    public static var current: UNUserNotificationCenter { .init() }
    public func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping (Bool, Error?) -> Void) {}
    public func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {}
    public func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {}
}
public struct UNAuthorizationOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 2)
}
public class UNNotificationRequest {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {}
}
public class UNNotificationContent {
    public var title: String = ""
    public var subtitle: String = ""
    public var body: String = ""
    public var sound: UNNotificationSound? = .default
}
public class UNNotificationTrigger {
    public let repeats: Bool
    public init(repeats: Bool) {}
}
public class UNNotification: NSObject {
    public let request: UNNotificationRequest
    public let date: Date
}
public typealias UNNotificationCompletionHandler = (Error?) -> Void
#endif