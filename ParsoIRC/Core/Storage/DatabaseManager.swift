import Foundation
import SQLite

final class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: Connection?
    private let dbPath: String
    
    // Tables
    private let servers = Table("servers")
    private let channels = Table("channels")
    private let messages = Table("messages")
    private let settings = Table("settings")
    
    // Server columns
    private let serverId = Expression<String>("id")
    private let serverName = Expression<String>("name")
    private let serverHost = Expression<String>("host")
    private let serverPort = Expression<Int>("port")
    private let serverSsl = Expression<Int>("ssl")
    private let serverNickname = Expression<String?>("nickname")
    private let serverRealname = Expression<String?>("realname")
    private let serverPassword = Expression<String?>("password")
    private let serverSaslEnabled = Expression<Int>("sasl_enabled")
    private let serverSaslMechanism = Expression<String?>("sasl_mechanism")
    private let serverAutoConnect = Expression<Int>("auto_connect")
    private let serverCreatedAt = Expression<String>("created_at")
    private let serverLastConnected = Expression<String?>("last_connected")
    
    // Channel columns
    private let channelId = Expression<String>("id")
    private let channelServerId = Expression<String>("server_id")
    private let channelName = Expression<String>("name")
    private let channelTopic = Expression<String?>("topic")
    private let channelMuted = Expression<Int>("is_muted")
    private let channelNotifications = Expression<String>("notifications")
    private let channelLastReadMessageId = Expression<String?>("last_read_message_id")
    private let channelJoinedAt = Expression<String?>("joined_at")
    private let channelIsWatched = Expression<Int>("is_watched")
    private let channelLastNotifiedAt = Expression<String?>("last_notified_at")
    private let channelLastCheckedAt = Expression<String?>("last_checked_at")
    private let channelNotifyOnAnyMessage = Expression<Int>("notify_on_any_message")
    
    // Message columns
    private let messageId = Expression<String>("id")
    private let messageChannelId = Expression<String>("channel_id")
    private let messageSender = Expression<String?>("sender")
    private let messageSenderHost = Expression<String?>("sender_host")
    private let messageContent = Expression<String>("content")
    private let messageTimestamp = Expression<String>("timestamp")
    private let messageType = Expression<String>("type")
    private let messageIsRead = Expression<Int>("is_read")
    private let messageCreatedAt = Expression<String>("created_at")
    
    // Settings columns
    private let settingKey = Expression<String>("key")
    private let settingValue = Expression<String?>("value")
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        dbPath = documentsPath.appendingPathComponent("parsoirc.sqlite3").path
        
        do {
            db = try Connection(dbPath)
            createTables()
        } catch {
            print("Database connection failed: \(error)")
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        
        do {
            try db.run(servers.create(ifNotExists: true) { t in
                t.column(serverId, primaryKey: true)
                t.column(serverName)
                t.column(serverHost)
                t.column(serverPort, defaultValue: 6697)
                t.column(serverSsl, defaultValue: 1)
                t.column(serverNickname)
                t.column(serverRealname)
                t.column(serverPassword)
                t.column(serverSaslEnabled, defaultValue: 0)
                t.column(serverSaslMechanism, defaultValue: "PLAIN")
                t.column(serverAutoConnect, defaultValue: 1)
                t.column(serverCreatedAt)
                t.column(serverLastConnected)
            })
            
            try db.run(channels.create(ifNotExists: true) { t in
                t.column(channelId, primaryKey: true)
                t.column(channelServerId)
                t.column(channelName)
                t.column(channelTopic)
                t.column(channelMuted, defaultValue: 0)
                t.column(channelNotifications, defaultValue: "mentions")
                t.column(channelLastReadMessageId)
                t.column(channelJoinedAt)
                t.column(channelIsWatched, defaultValue: 0)
                t.column(channelLastNotifiedAt)
                t.column(channelLastCheckedAt)
                t.column(channelNotifyOnAnyMessage, defaultValue: 0)
                t.unique(channelServerId, channelName)
            })
            
            try db.run(messages.create(ifNotExists: true) { t in
                t.column(messageId, primaryKey: true)
                t.column(messageChannelId)
                t.column(messageSender)
                t.column(messageSenderHost)
                t.column(messageContent)
                t.column(messageTimestamp)
                t.column(messageType, defaultValue: "message")
                t.column(messageIsRead, defaultValue: 0)
                t.column(messageCreatedAt)
            })
            
            try db.run(messages.createIndex(messageChannelId, messageTimestamp, ifNotExists: true))
            
            try db.run(settings.create(ifNotExists: true) { t in
                t.column(settingKey, primaryKey: true)
                t.column(settingValue)
            })
        } catch {
            print("Table creation failed: \(error)")
        }
    }
    
    // MARK: - Server Operations
    
    func saveServer(_ server: Server) throws {
        guard let db = db else { return }
        
        let insert = servers.insert(or: .replace,
            serverId <- server.id,
            serverName <- server.name,
            serverHost <- server.host,
            serverPort <- server.port,
            serverSsl <- server.ssl ? 1 : 0,
            serverNickname <- server.nickname,
            serverRealname <- server.realname,
            serverPassword <- server.password,
            serverSaslEnabled <- server.saslEnabled ? 1 : 0,
            serverSaslMechanism <- server.saslMechanism,
            serverAutoConnect <- server.autoConnect ? 1 : 0,
            serverCreatedAt <- dateFormatter.string(from: server.createdAt),
            serverLastConnected <- server.lastConnected.map { dateFormatter.string(from: $0) }
        )
        
        try db.run(insert)
        
        for channel in server.channels {
            try saveChannel(channel, serverId: server.id)
        }
    }
    
    func fetchServers() throws -> [Server] {
        guard let db = db else { return [] }
        
        var result: [Server] = []
        
        for row in try db.prepare(servers) {
            let serverChannels = try fetchChannels(forServer: row[serverId])
            
            let server = Server(
                id: row[serverId],
                name: row[serverName],
                host: row[serverHost],
                port: row[serverPort],
                ssl: row[serverSsl] == 1,
                nickname: row[serverNickname] ?? "",
                realname: row[serverRealname] ?? "",
                password: row[serverPassword],
                saslEnabled: row[serverSaslEnabled] == 1,
                saslMechanism: row[serverSaslMechanism] ?? "PLAIN",
                autoConnect: row[serverAutoConnect] == 1,
                createdAt: dateFormatter.date(from: row[serverCreatedAt]) ?? Date(),
                lastConnected: row[serverLastConnected].flatMap { dateFormatter.date(from: $0) },
                isConnected: false,
                channels: serverChannels
            )
            result.append(server)
        }
        
        return result
    }
    
    func deleteServer(id: String) throws {
        guard let db = db else { return }
        
        let server = servers.filter(serverId == id)
        try db.run(server.delete())
        
        let serverChannels = channels.filter(channelServerId == id)
        try db.run(serverChannels.delete())
        
        // Messages will be deleted via cascade or manually
    }
    
    // MARK: - Channel Operations
    
    func saveChannel(_ channel: Channel, serverId sid: String) throws {
        guard let db = db else { return }
        
        let insert = channels.insert(or: .replace,
            channelId <- channel.id,
            channelServerId <- sid,
            channelName <- channel.name,
            channelTopic <- channel.topic,
            channelMuted <- channel.isMuted ? 1 : 0,
            channelNotifications <- channel.notifications.rawValue,
            channelLastReadMessageId <- channel.lastReadMessageId,
            channelJoinedAt <- channel.joinedAt.map { dateFormatter.string(from: $0) },
            channelIsWatched <- channel.isWatched ? 1 : 0,
            channelLastNotifiedAt <- channel.lastNotifiedAt.map { dateFormatter.string(from: $0) },
            channelLastCheckedAt <- channel.lastCheckedAt.map { dateFormatter.string(from: $0) },
            channelNotifyOnAnyMessage <- channel.notifyOnAnyMessage ? 1 : 0
        )
        
        try db.run(insert)
    }
    
    func fetchChannels(forServer sid: String) throws -> [Channel] {
        guard let db = db else { return [] }
        
        var result: [Channel] = []
        let query = channels.filter(channelServerId == sid)
        
        for row in try db.prepare(query) {
            let channel = Channel(
                id: row[channelId],
                serverId: row[channelServerId],
                name: row[channelName],
                topic: row[channelTopic],
                isMuted: row[channelMuted] == 1,
                notifications: Channel.NotificationLevel(rawValue: row[channelNotifications]) ?? .mentions,
                lastReadMessageId: row[channelLastReadMessageId],
                joinedAt: row[channelJoinedAt].flatMap { dateFormatter.date(from: $0) },
                isWatched: row[channelIsWatched] == 1,
                lastNotifiedAt: row[channelLastNotifiedAt].flatMap { dateFormatter.date(from: $0) },
                lastCheckedAt: row[channelLastCheckedAt].flatMap { dateFormatter.date(from: $0) },
                notifyOnAnyMessage: row[channelNotifyOnAnyMessage] == 1
            )
            result.append(channel)
        }
        
        return result
    }
    
    // MARK: - Watch Channel Operations
    
    func getWatchedChannels() throws -> [Channel] {
        guard let db = db else { return [] }
        
        var result: [Channel] = []
        let query = channels.filter(channelIsWatched == 1)
        
        for row in try db.prepare(query) {
            let channel = Channel(
                id: row[channelId],
                serverId: row[channelServerId],
                name: row[channelName],
                topic: row[channelTopic],
                isMuted: row[channelMuted] == 1,
                notifications: Channel.NotificationLevel(rawValue: row[channelNotifications]) ?? .mentions,
                lastReadMessageId: row[channelLastReadMessageId],
                joinedAt: row[channelJoinedAt].flatMap { dateFormatter.date(from: $0) },
                isWatched: true,
                lastNotifiedAt: row[channelLastNotifiedAt].flatMap { dateFormatter.date(from: $0) },
                lastCheckedAt: row[channelLastCheckedAt].flatMap { dateFormatter.date(from: $0) },
                notifyOnAnyMessage: row[channelNotifyOnAnyMessage] == 1
            )
            result.append(channel)
        }
        
        return result
    }
    
    func getLatestMessage(forChannel cid: String) throws -> Message? {
        guard let db = db else { return nil }
        
        let query = messages
            .filter(messageChannelId == cid)
            .order(messageTimestamp.desc)
            .limit(1)
        
        for row in try db.prepare(query) {
            return Message(
                id: row[messageId],
                channelId: row[messageChannelId],
                sender: row[messageSender] ?? "",
                senderHost: row[messageSenderHost],
                content: row[messageContent],
                timestamp: dateFormatter.date(from: row[messageTimestamp]) ?? Date(),
                type: Message.MessageType(rawValue: row[messageType]) ?? .message,
                isRead: row[messageIsRead] == 1
            )
        }
        
        return nil
    }
    
    // MARK: - Message Operations
    
    func saveMessage(_ message: Message) throws {
        guard let db = db else { return }
        
        let insert = messages.insert(or: .replace,
            messageId <- message.id,
            messageChannelId <- message.channelId,
            messageSender <- message.sender,
            messageSenderHost <- message.senderHost,
            messageContent <- message.content,
            messageTimestamp <- dateFormatter.string(from: message.timestamp),
            messageType <- message.type.rawValue,
            messageIsRead <- message.isRead ? 1 : 0,
            messageCreatedAt <- dateFormatter.string(from: Date())
        )
        
        try db.run(insert)
    }
    
    func fetchMessages(forChannel cid: String, limit: Int = 1000) throws -> [Message] {
        guard let db = db else { return [] }
        
        var result: [Message] = []
        let query = messages
            .filter(messageChannelId == cid)
            .order(messageTimestamp.desc)
            .limit(limit)
        
        for row in try db.prepare(query) {
            let message = Message(
                id: row[messageId],
                channelId: row[messageChannelId],
                sender: row[messageSender] ?? "",
                senderHost: row[messageSenderHost],
                content: row[messageContent],
                timestamp: dateFormatter.date(from: row[messageTimestamp]) ?? Date(),
                type: Message.MessageType(rawValue: row[messageType]) ?? .message,
                isRead: row[messageIsRead] == 1
            )
            result.append(message)
        }
        
        return result.reversed()
    }
    
    func deleteOldMessages(olderThan date: Date, maxPerChannel: Int) throws {
        guard let db = db else { return }
        
        let cutoffDate = dateFormatter.string(from: date)
        
        // Get all channel IDs - use a subquery approach
        let allChannelIds = try db.prepare(messages.select(messageChannelId)).map { $0[messageChannelId] }
        let uniqueChannelIds = Array(Set(allChannelIds))
        
        for channelId in uniqueChannelIds {
            let channelMessages = messages
                .filter(messageChannelId == channelId)
                .order(messageTimestamp.desc)
                .limit(maxPerChannel, offset: maxPerChannel)
            
            let idsToDelete = try db.prepare(channelMessages).map { $0[messageId] }
            
            if !idsToDelete.isEmpty {
                let deleteQuery = messages.filter(idsToDelete.contains(messageId))
                try db.run(deleteQuery.delete())
            }
            
            let oldMessages = messages
                .filter(messageChannelId == channelId)
                .filter(messageTimestamp < cutoffDate)
            
            try db.run(oldMessages.delete())
        }
    }
    
    func searchMessages(query: String, inChannel cid: String? = nil) throws -> [Message] {
        guard let db = db else { return [] }
        
        var result: [Message] = []
        var searchQuery = messages.filter(messageContent.like("%\(query)%"))
        
        if let channelId = cid {
            searchQuery = searchQuery.filter(messageChannelId == channelId)
        }
        
        for row in try db.prepare(searchQuery.order(messageTimestamp.desc).limit(100)) {
            let message = Message(
                id: row[messageId],
                channelId: row[messageChannelId],
                sender: row[messageSender] ?? "",
                senderHost: row[messageSenderHost],
                content: row[messageContent],
                timestamp: dateFormatter.date(from: row[messageTimestamp]) ?? Date(),
                type: Message.MessageType(rawValue: row[messageType]) ?? .message,
                isRead: row[messageIsRead] == 1
            )
            result.append(message)
        }
        
        return result
    }
    
    // MARK: - Settings Operations
    
    func saveSetting(key: String, value: String?) throws {
        guard let db = db else { return }
        
        let insert = settings.insert(or: .replace,
            settingKey <- key,
            settingValue <- value
        )
        
        try db.run(insert)
    }
    
    func fetchSetting(key: String) throws -> String? {
        guard let db = db else { return nil }
        
        let query = settings.filter(settingKey == key)
        
        for row in try db.prepare(query) {
            return row[settingValue]
        }
        
        return nil
    }
    
    // MARK: - Cleanup
    
    func cleanupOldData() throws {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        try deleteOldMessages(olderThan: thirtyDaysAgo, maxPerChannel: 1000)
    }
}