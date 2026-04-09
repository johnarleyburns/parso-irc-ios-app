import XCTest
@testable import ParsoIRC

final class DateFormattingTests: XCTestCase {
    
    // MARK: - Formatted Time Tests
    
    func testFormattedTime_returns12HourFormat() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 15
        components.hour = 14
        components.minute = 30
        
        guard let date = calendar.date(from: components) else {
            XCTFail("Could not create date")
            return
        }
        
        let formatted = date.formattedTime()
        
        // Should contain "2:30" (14:30 = 2:30 in 12-hour)
        XCTAssertTrue(formatted.contains("2:30"))
    }
    
    // MARK: - Time Ago Tests
    
    func testTimeAgo_returnsRelativeString() {
        let recent = Date().addingTimeInterval(-60) // 1 minute ago
        let ago = recent.timeAgo()
        
        // Should contain something like "1m ago" or "just now"
        XCTAssertFalse(ago.isEmpty)
    }
    
    // MARK: - Same Day Tests
    
    func testIsSameDay_comparesCalendarDays() {
        let calendar = Calendar.current
        
        var components1 = DateComponents()
        components1.year = 2024
        components1.month = 1
        components1.day = 15
        components1.hour = 10
        components1.minute = 0
        
        var components2 = DateComponents()
        components2.year = 2024
        components2.month = 1
        components2.day = 15
        components2.hour = 22
        components2.minute = 0
        
        guard let date1 = calendar.date(from: components1),
              let date2 = calendar.date(from: components2) else {
            XCTFail("Could not create dates")
            return
        }
        
        XCTAssertTrue(date1.isSameDay(as: date2))
    }
    
    func testIsSameDay_differentDays() {
        let calendar = Calendar.current
        
        var components1 = DateComponents()
        components1.year = 2024
        components1.month = 1
        components1.day = 15
        
        var components2 = DateComponents()
        components2.year = 2024
        components2.month = 1
        components2.day = 16
        
        guard let date1 = calendar.date(from: components1),
              let date2 = calendar.date(from: components2) else {
            XCTFail("Could not create dates")
            return
        }
        
        XCTAssertFalse(date1.isSameDay(as: date2))
    }
    
    // MARK: - Today/Yesterday Tests
    
    func testIsToday_detectsToday() {
        XCTAssertTrue(Date().isToday)
    }
    
    func testIsYesterday_detectsYesterday() {
        XCTAssertTrue(Date().addingTimeInterval(-86400).isYesterday)
    }
    
    func testIsToday_doesNotDetectYesterday() {
        XCTAssertFalse(Date().addingTimeInterval(-86400).isToday)
    }
    
    // MARK: - Formatted Date Tests
    
    func testFormattedDate_returnsTodayForToday() {
        let today = Date()
        XCTAssertEqual(today.formattedDate(), "Today")
    }
    
    func testFormattedDate_returnsYesterdayForYesterday() {
        let yesterday = Date().addingTimeInterval(-86400)
        XCTAssertEqual(yesterday.formattedDate(), "Yesterday")
    }
    
    func testFormattedDate_returnsMonthDayYearForPast() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 15
        
        guard let pastDate = calendar.date(from: components) else {
            XCTFail("Could not create date")
            return
        }
        
        let formatted = pastDate.formattedDate()
        
        // Should return something like "March 15, 2024"
        XCTAssertTrue(formatted.contains("March"))
        XCTAssertTrue(formatted.contains("15"))
        XCTAssertTrue(formatted.contains("2024"))
    }
}