import XCTest
@testable import ParsoIRC

final class WatchManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: "watch_settings")
        UserDefaults.standard.removeObject(forKey: "last_notification_sent")
    }
    
    override func tearDown() {
        super.tearDown()
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: "watch_settings")
        UserDefaults.standard.removeObject(forKey: "last_notification_sent")
    }
    
    // MARK: - Default Settings Tests
    
    func testDefaultSettings_hasExpectedDefaults() {
        let defaults = WatchSettings.default
        
        XCTAssertEqual(defaults.pollIntervalMinutes, 5)
        XCTAssertTrue(defaults.notificationsEnabled)
        XCTAssertEqual(defaults.debounceSeconds, 60)
        XCTAssertTrue(defaults.showPreviewInNotification)
    }
    
    // MARK: - Poll Interval Tests
    
    func testUpdatePollInterval_clampedToValidRange() {
        let manager = WatchManager.shared
        
        // Test upper bound (should clamp to 5)
        manager.updatePollInterval(10)
        XCTAssertEqual(manager.settings.pollIntervalMinutes, 5)
        
        // Test lower bound (should clamp to 1)
        manager.updatePollInterval(0)
        XCTAssertEqual(manager.settings.pollIntervalMinutes, 1)
        
        // Test negative (should clamp to 1)
        manager.updatePollInterval(-5)
        XCTAssertEqual(manager.settings.pollIntervalMinutes, 1)
    }
    
    func testUpdatePollInterval_allowsBoundaryValues() {
        let manager = WatchManager.shared
        
        manager.updatePollInterval(1)
        XCTAssertEqual(manager.settings.pollIntervalMinutes, 1)
        
        manager.updatePollInterval(5)
        XCTAssertEqual(manager.settings.pollIntervalMinutes, 5)
    }
    
    func testUpdatePollInterval_allowsMiddleValues() {
        let manager = WatchManager.shared
        
        manager.updatePollInterval(3)
        XCTAssertEqual(manager.settings.pollIntervalMinutes, 3)
    }
    
    // MARK: - Notification Authorization Tests
    
    func testCanSendNotification_whenEnabledAndNoPreviousNotification() {
        let manager = WatchManager.shared
        manager.toggleNotifications(true)
        
        // Clear any previous notification
        manager.lastNotificationSent = nil
        
        XCTAssertTrue(manager.canSendNotification())
    }
    
    func testCanSendNotification_blocksWithinDebounceWindow() {
        let manager = WatchManager.shared
        manager.toggleNotifications(true)
        
        // Set notification sent just 10 seconds ago (debounce is 60s)
        manager.recordNotificationSent()
        
        XCTAssertFalse(manager.canSendNotification())
    }
    
    func testCanSendNotification_allowsAfterDebouncePeriod() {
        let manager = WatchManager.shared
        manager.toggleNotifications(true)
        
        // Record notification sent 90 seconds ago (debounce is 60s)
        let oldDate = Date().addingTimeInterval(-90)
        manager.lastNotificationSent = oldDate
        
        XCTAssertTrue(manager.canSendNotification())
    }
    
    func testCanSendNotification_returnsFalseWhenDisabled() {
        let manager = WatchManager.shared
        manager.toggleNotifications(false)
        
        XCTAssertFalse(manager.canSendNotification())
    }
    
    // MARK: - Record Notification Tests
    
    func testRecordNotificationSent_updatesTimestamp() {
        let manager = WatchManager.shared
        
        let before = Date()
        manager.recordNotificationSent()
        let after = Date()
        
        guard let lastSent = manager.lastNotificationSent else {
            XCTFail("lastNotificationSent should not be nil")
            return
        }
        
        XCTAssertTrue(lastSent >= before && lastSent <= after)
    }
    
    // MARK: - Save/Load Settings Tests
    
    func testSaveSettings_persistsToUserDefaults() {
        let manager = WatchManager.shared
        
        manager.settings.pollIntervalMinutes = 3
        manager.settings.notificationsEnabled = false
        manager.settings.showPreviewInNotification = false
        manager.saveSettings()
        
        // Create new manager instance to test loading
        let freshManager = WatchManager.shared
        
        XCTAssertEqual(freshManager.settings.pollIntervalMinutes, 3)
        XCTAssertFalse(freshManager.settings.notificationsEnabled)
        XCTAssertFalse(freshManager.settings.showPreviewInNotification)
    }
    
    // MARK: - Toggle Tests
    
    func testToggleNotifications_setsValue() {
        let manager = WatchManager.shared
        
        manager.toggleNotifications(false)
        XCTAssertFalse(manager.settings.notificationsEnabled)
        
        manager.toggleNotifications(true)
        XCTAssertTrue(manager.settings.notificationsEnabled)
    }
    
    func testTogglePreview_setsValue() {
        let manager = WatchManager.shared
        
        manager.togglePreview(false)
        XCTAssertFalse(manager.settings.showPreviewInNotification)
        
        manager.togglePreview(true)
        XCTAssertTrue(manager.settings.showPreviewInNotification)
    }
}