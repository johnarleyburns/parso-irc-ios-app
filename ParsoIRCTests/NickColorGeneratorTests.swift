import XCTest
@testable import ParsoIRC

final class NickColorGeneratorTests: XCTestCase {
    
    // MARK: - Deterministic Behavior Tests
    
    func testColorForNick_isDeterministic() {
        let color1 = NickColorGenerator.color(for: "alice")
        let color2 = NickColorGenerator.color(for: "alice")
        
        XCTAssertEqual(color1, color2)
    }
    
    func testColorForNick_sameInputReturnsSameOutput() {
        let color = NickColorGenerator.color(for: "bob")
        
        // Call multiple times - should always return same color
        for _ in 0..<10 {
            XCTAssertEqual(color, NickColorGenerator.color(for: "bob"))
        }
    }
    
    func testColorForNick_differentInputsMayReturnDifferent() {
        let color1 = NickColorGenerator.color(for: "alice")
        let color2 = NickColorGenerator.color(for: "bob")
        
        // Not guaranteed to be different, but very likely
        // This test just ensures no crash and values are returned
        XCTAssertNotNil(color1)
        XCTAssertNotNil(color2)
    }
    
    // MARK: - Edge Case Tests
    
    func testColorForNick_handlesEmptyString() {
        let color = NickColorGenerator.color(for: "")
        
        // Should not crash and return valid color
        XCTAssertNotNil(color)
    }
    
    func testColorForNick_handlesUnicode() {
        let color = NickColorGenerator.color(for: "用户")
        
        // Should not crash and return valid color
        XCTAssertNotNil(color)
    }
    
    func testColorForNick_handlesVeryLongString() {
        let longNick = String(repeating: "a", count: 1000)
        let color = NickColorGenerator.color(for: longNick)
        
        // Should not crash and return valid color
        XCTAssertNotNil(color)
    }
    
    func testColorForNick_handlesSpecialCharacters() {
        let color = NickColorGenerator.color(for: "alice[work]")
        
        // Should not crash and return valid color
        XCTAssertNotNil(color)
    }
    
    // MARK: - Color Distribution Tests
    
    func testColorGenerator_hasMultipleColors() {
        var colors: Set<String> = []
        
        // Generate colors for many different nicks
        for i in 0..<50 {
            let color = NickColorGenerator.color(for: "user\(i)")
            colors.insert("\(color)")
        }
        
        // Should have multiple different colors (not all same)
        XCTAssertGreaterThan(colors.count, 1)
    }
    
    func testColorGenerator_doesNotAlwaysReturnSameColor() {
        let colors = (0..<20).map { NickColorGenerator.color(for: "user\($0)") }
        
        // At least some should be different
        let uniqueColors = Set(colors)
        XCTAssertGreaterThan(uniqueColors.count, 1)
    }
    
    // MARK: - UI Color Tests
    
    func testUIColor_returnsValidUIColor() {
        let uiColor = NickColorGenerator.uiColor(for: "test")
        
        // Should return a valid UIColor
        XCTAssertNotNil(uiColor)
    }
}