import XCTest

class SignUpWorkflowTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset"]
    }
    
    override func tearDown() {
        app = nil
        super.tearDown()
    }
    
    // MARK: - Full Sign Up Flow Test
    
    func testCompleteSignUpFlow() throws {
        app.launch()
        
        // ===== Step 1: Splash Screen =====
        XCTAssertTrue(app.staticTexts["Parso"].waitForExistence(timeout: 5))
        app.tap()
        
        // ===== Step 2: Onboarding Pages =====
        let nextButton = app.buttons["nextButton"]
        
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        nextButton.tap()
        nextButton.tap()
        
        // ===== Step 3: Onboarding Final Page =====
        let onboardingSignUp = app.buttons["onboardingSignUpButton"]
        XCTAssertTrue(onboardingSignUp.waitForExistence(timeout: 5))
        onboardingSignUp.tap()
        
        // ===== Step 4: Registration View =====
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        
        usernameField.tap()
        app.typeText("testuser\(Int.random(in: 1000...9999))")
        
        // ===== Step 5: Submit Registration =====
        let signUpButton = app.buttons["signUpButton"]
        XCTAssertTrue(signUpButton.waitForExistence(timeout: 5))
        signUpButton.tap()
        
        // ===== Step 6: Verify Spinner Appears =====
        let progressView = app.progressIndicators.element
        XCTAssertTrue(progressView.waitForExistence(timeout: 30))
        
        // ===== Step 7: Wait for IRC Connection & Chat View =====
        let chatNavigationTitle = app.staticTexts["#linux"]
        XCTAssertTrue(chatNavigationTitle.waitForExistence(timeout: 60))
        
        // ===== Step 8: Verify Chat Screen =====
        let messageInput = app.textFields["messageInput"]
        XCTAssertTrue(messageInput.waitForExistence(timeout: 5))
    }
    
    // MARK: - Cancel Button Test
    
    func testCancelButtonNavigatesToHome() throws {
        app.launch()
        
        app.tap()
        
        let nextButton = app.buttons["nextButton"]
        _ = nextButton.waitForExistence(timeout: 5)
        nextButton.tap()
        nextButton.tap()
        nextButton.tap()
        
        let signInButton = app.buttons["onboardingSignInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        signInButton.tap()
        
        let cancelButton = app.buttons["cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
        
        let tabBar = app.tabBars.element
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
    }
}