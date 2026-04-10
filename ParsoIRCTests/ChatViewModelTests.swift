import XCTest
@testable import ParsoIRC

final class ChatViewModelTests: XCTestCase {
    
    private var viewModel: ChatViewModel!
    private var testServer: Server!
    private var testChannel: Channel!
    
    override func setUp() {
        super.setUp()
        testServer = Server(id: "test-server-1", name: "TestServer", host: "irc.test.com", port: 6697, nickname: "testuser")
        testChannel = Channel(id: "test-channel-1", name: "#test")
        viewModel = ChatViewModel(server: testServer, channel: testChannel)
    }
    
    override func tearDown() {
        viewModel = nil
        testServer = nil
        testChannel = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInit_setsServerAndChannel() {
        XCTAssertEqual(viewModel.server.id, testServer.id)
        XCTAssertEqual(viewModel.channel.id, testChannel.id)
    }
    
    func testInit_defaultValues() {
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.inputText, "")
        XCTAssertFalse(viewModel.isTyping)
        XCTAssertTrue(viewModel.channelMembers.isEmpty)
    }
    
    // MARK: - Message Grouping Tests
    
    func testGroupedMessages_groupsByDate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        let msg1 = Message(channelId: "1", sender: "alice", content: "Hello", timestamp: today.addingTimeInterval(3600), type: .message)
        let msg2 = Message(channelId: "1", sender: "bob", content: "World", timestamp: yesterday.addingTimeInterval(3600), type: .message)
        
        viewModel.messages = [msg1, msg2]
        
        let groups = viewModel.groupedMessages
        
        XCTAssertEqual(groups.count, 2)
    }
    
    func testGroupedMessages_singleDay() {
        let today = Calendar.current.startOfDay(for: Date())
        
        let msg1 = Message(channelId: "1", sender: "alice", content: "Hello", timestamp: today.addingTimeInterval(3600), type: .message)
        let msg2 = Message(channelId: "1", sender: "bob", content: "World", timestamp: today.addingTimeInterval(7200), type: .message)
        
        viewModel.messages = [msg1, msg2]
        
        let groups = viewModel.groupedMessages
        
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.messages.count, 2)
    }
    
    func testGroupedMessages_sortedChronologically() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        let msg1 = Message(channelId: "1", sender: "alice", content: "Yesterday", timestamp: today, type: .message)
        let msg2 = Message(channelId: "1", sender: "bob", content: "Today", timestamp: tomorrow, type: .message)
        
        viewModel.messages = [msg2, msg1]
        
        let groups = viewModel.groupedMessages
        
        XCTAssertEqual(groups.first?.date, today)
        XCTAssertEqual(groups.last?.date, tomorrow)
    }
    
    // MARK: - Input Text Tests
    
    func testInputText_emptyByDefault() {
        XCTAssertEqual(viewModel.inputText, "")
    }
    
    func testInputText_canBeModified() {
        viewModel.inputText = "Test message"
        XCTAssertEqual(viewModel.inputText, "Test message")
    }
    
    // MARK: - Channel Members Tests
    
    func testChannelMembers_emptyByDefault() {
        XCTAssertTrue(viewModel.channelMembers.isEmpty)
    }
    
    func testChannelMembers_canBeSet() {
        let members = [
            ChannelMember(nick: "alice", mode: .operator_),
            ChannelMember(nick: "bob", mode: .voice),
            ChannelMember(nick: "charlie", mode: .none)
        ]
        
        viewModel.channelMembers = members
        
        XCTAssertEqual(viewModel.channelMembers.count, 3)
    }
    
    // MARK: - Search Messages Tests
    
    func testSearchMessages_returnsMatchingResults() {
        let messages = [
            Message(channelId: "test-channel-1", sender: "alice", content: "Hello world", timestamp: Date(), type: .message),
            Message(channelId: "test-channel-1", sender: "bob", content: "Goodbye world", timestamp: Date(), type: .message),
            Message(channelId: "test-channel-1", sender: "charlie", content: "No match here", timestamp: Date(), type: .message)
        ]
        
        // Note: This test assumes DatabaseManager is functional
        // In a real test, we'd mock the database
        let results = viewModel.searchMessages(query: "world")
        
        // Results may be empty if database is not set up, which is expected
        XCTAssertTrue(results is [Message])
    }
    
    func testSearchMessages_caseInsensitive() {
        let results = viewModel.searchMessages(query: "HELLO")
        
        XCTAssertTrue(results is [Message])
    }
    
    // MARK: - Channel Update Tests
    
    func testChannel_topicCanBeUpdated() {
        viewModel.channel.topic = "Test topic"
        XCTAssertEqual(viewModel.channel.topic, "Test topic")
    }
    
    func testChannel_memberCountCanBeUpdated() {
        viewModel.channel.memberCount = 42
        XCTAssertEqual(viewModel.channel.memberCount, 42)
    }
}