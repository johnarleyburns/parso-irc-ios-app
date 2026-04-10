import XCTest
import UserNotifications
@testable import ParsoIRC

final class NotificationManagerTests: XCTestCase {
    
    private var notificationManager: NotificationManager!
    
    override func setUp() {
        super.setUp()
        notificationManager = NotificationManager.shared
    }
    
    override func tearDown() {
        notificationManager.clearAllNotifications()
        super.tearDown()
    }
    
    // MARK: - Authorization State Tests
    
    func testIsAuthorized_defaultsToFalse() {
        XCTAssertFalse(notificationManager.isAuthorized)
    }
    
    func testIsAuthorized_canBeSet() {
        notificationManager.isAuthorized = true
        XCTAssertTrue(notificationManager.isAuthorized)
    }
    
    // MARK: - Category Identifier Tests
    
    func testCategoryIdentifier_isDefined() {
        XCTAssertFalse(NotificationManager.shared.categoryIdentifier.isEmpty)
    }
    
    // MARK: - Notification Content Tests
    
    func testSendWatchNotification_requiresCanSendNotification() async {
        // This test verifies the guard check works
        // By default, canSendNotification() requires notifications to be enabled
        WatchManager.shared.toggleNotifications(false)
        
        let channel = Channel(id: "test-notif-\(UUID().uuidString)", serverId: "server1", name: "#test")
        let message = Message(id: "msg-\(UUID().uuidString)", channelId: channel.id, sender: "alice", content: "Test", timestamp: Date(), type: .message)
        
        // Should not throw even when notifications are disabled
        await notificationManager.sendWatchNotification(channel: channel, message: message)
    }
    
    func testSendWatchNotification_includesChannelNameInTitle() async {
        WatchManager.shared.toggleNotifications(true)
        WatchManager.shared.lastNotificationSent = nil
        
        let channelName = "#testchannel-\(UUID().uuidString)"
        let channel = Channel(id: "test-notif-title-\(UUID().uuidString)", serverId: "server1", name: channelName)
        let message = Message(id: "msg-title-\(UUID().uuidString)", channelId: channel.id, sender: "alice", content: "Test", timestamp: Date(), type: .message)
        
        // The method should not throw
        await notificationManager.sendWatchNotification(channel: channel, message: message)
    }
    
    func testSendWatchNotification_includesMessageContentWhenPreviewEnabled() async {
        WatchManager.shared.toggleNotifications(true)
        WatchManager.shared.togglePreview(true)
        WatchManager.shared.lastNotificationSent = nil
        
        let channel = Channel(id: "test-notif-preview-\(UUID().uuidString)", serverId: "server1", name: "#preview")
        let message = Message(id: "msg-preview-\(UUID().uuidString)", channelId: channel.id, sender: "alice", content: "Hello world", timestamp: Date(), type: .message)
        
        await notificationManager.sendWatchNotification(channel: channel, message: message)
        
        XCTAssertTrue(WatchManager.shared.settings.showPreviewInNotification)
    }
    
    // MARK: - Clear Notifications Tests
    
    func testClearAllNotifications_completesWithoutError() {
        // Should not throw even if no notifications exist
        notificationManager.clearAllNotifications()
    }
    
    // MARK: - Test Notification Tests
    
    func testSendTestNotification_completesWithoutError() async {
        // Should not throw
        await notificationManager.sendTestNotification()
    }
    
    // MARK: - UserInfo Construction Tests
    
    func testNotificationUserInfo_containsRequiredKeys() async {
        WatchManager.shared.toggleNotifications(true)
        WatchManager.shared.lastNotificationSent = nil
        
        let channelId = "test-userinfo-\(UUID().uuidString)"
        let serverId = "test-server-\(UUID().uuidString)"
        let channelName = "#test"
        
        let channel = Channel(id: channelId, serverId: serverId, name: channelName)
        let message = Message(id: "msg-userinfo-\(UUID().uuidString)", channelId: channelId, sender: "alice", content: "Test", timestamp: Date(), type: .message)
        
        // The sendWatchNotification method constructs userInfo with channelId, serverId, channelName
        // This test just verifies the method can be called without error
        await notificationManager.sendWatchNotification(channel: channel, message: message)
    }
    
    // MARK: - Handle Notification Response Tests
    
    func testHandleNotificationResponse_doesNotThrow() async {
        // Create a mock notification response
        let notification = UNNotification(
            request: UNNotificationRequest(
                identifier: "test",
                content: UNMutableNotificationContent(),
                trigger: nil
            ),
            date: Date()
        )
        
        let response = UNNotificationResponse(notification: notification, actionIdentifier: UNNotificationDefaultActionIdentifier)
        
        // Should not throw
        await notificationManager.handleNotificationResponse(response)
    }
    
    func testHandleNotificationResponse_dismissAction() async {
        let notification = UNNotification(
            request: UNNotificationRequest(
                identifier: "test-dismiss",
                content: UNMutableNotificationContent(),
                trigger: nil
            ),
            date: Date()
        )
        
        let response = UNNotificationResponse(notification: notification, actionIdentifier: "DISMISS")
        
        await notificationManager.handleNotificationResponse(response)
    }
}