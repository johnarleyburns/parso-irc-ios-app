// Stub for UserNotifications (Linux only)
#if os(Linux)
import Foundation
public class UNUserNotificationCenter {
    public static func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
    public var delegate: UNUserNotificationCenterDelegate?
    public func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping (Bool, Error?) -> Void) {}
    public func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool { false }
    public func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {}
    public func add(_ request: UNNotificationRequest) async throws {}
    public func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {}
    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    public func getNotificationCategories(completionHandler: @escaping (Set<UNNotificationCategory>) -> Void) {}
    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    public func removeAllDeliveredNotifications() {}
    public func removeAllPendingNotificationRequests() {}
    public func notificationSettings() async -> UNNotificationSettings { UNNotificationSettings() }
}
public class UNNotificationSettings {
    public var authorizationStatus: UNAuthorizationStatus = .notDetermined
}
public enum UNAuthorizationStatus {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}
public protocol UNUserNotificationCenterDelegate: AnyObject {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async
}
public struct UNAuthorizationOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let authorized = UNAuthorizationOptions(rawValue: 1 << 3)
    public static let empty = UNAuthorizationOptions(rawValue: 0)
}
public struct UNNotificationPresentationOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 2)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 3)
    public static let default_: UNNotificationPresentationOptions = [.banner, .sound]
    public static let all: UNNotificationPresentationOptions = [.banner, .list, .badge, .sound]
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
    public var userInfo: [AnyHashable: Any] = [:]
    public init() {}
}
public class UNMutableNotificationContent: UNNotificationContent {
    public var categoryIdentifier: String = ""
    public override init() {}
}
public class UNNotificationSound {
    public static var `default`: UNNotificationSound { UNNotificationSound() }
    public static var defaultSound: UNNotificationSound { UNNotificationSound() }
    public init() {}
}
public class UNNotificationTrigger {
    public let repeats: Bool
    public init(repeats: Bool) {}
}
public class UNNotification: NSObject {
    public let request: UNNotificationRequest
    public let date: Date
    public init(request: UNNotificationRequest, date: Date) {
        self.request = request
        self.date = date
    }
}
public class UNNotificationResponse: NSObject {
    public let notification: UNNotification
    public let actionIdentifier: String
    public init(notification: UNNotification, actionIdentifier: String) {
        self.notification = notification
        self.actionIdentifier = actionIdentifier
    }
}
public class UNNotificationAction: NSObject {
    public let identifier: String
    public let title: String
    public let options: UNNotificationActionOptions
    public init(identifier: String, title: String, options: UNNotificationActionOptions = []) {}
}
public struct UNNotificationActionOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let foreground = UNNotificationActionOptions(rawValue: 1 << 0)
    public static let destructive = UNNotificationActionOptions(rawValue: 1 << 1)
    public static let authenticationRequired = UNNotificationActionOptions(rawValue: 1 << 2)
}
public class UNNotificationCategory: NSObject, Hashable {
    public static func == (lhs: UNNotificationCategory, rhs: UNNotificationCategory) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
    public let identifier: String
    public let actions: [UNNotificationAction]
    public let intentIdentifiers: [String]
    public let options: UNNotificationCategoryOptions
    public init(identifier: String, actions: [UNNotificationAction] = [], intentIdentifiers: [String] = [], options: UNNotificationCategoryOptions = []) {}
}
public struct UNNotificationCategoryOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1 << 0)
}
public let UNNotificationDefaultActionIdentifier: String = "UNDefaultAction"
public typealias UNNotificationCompletionHandler = (Error?) -> Void
#endif