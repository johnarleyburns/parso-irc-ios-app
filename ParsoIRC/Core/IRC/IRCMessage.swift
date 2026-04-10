import Foundation

struct IRCUser: Hashable, Sendable {
    let nick: String
    let user: String?
    let host: String?

    init(nick: String, user: String? = nil, host: String? = nil) {
        self.nick = nick
        self.user = user
        self.host = host
    }

    init?(prefix: String) {
        guard !prefix.isEmpty else { return nil }

        if prefix.hasPrefix(":") {
            let trimmed = String(prefix.dropFirst())
            if let bangIndex = trimmed.firstIndex(of: "!") {
                self.nick = String(trimmed[..<bangIndex])
                let rest = String(trimmed[trimmed.index(after: bangIndex)...])
                if let atIndex = rest.firstIndex(of: "@") {
                    self.user = String(rest[..<atIndex])
                    self.host = String(rest[rest.index(after: atIndex)...])
                } else {
                    self.user = rest
                    self.host = nil
                }
            } else {
                self.nick = trimmed
                self.user = nil
                self.host = nil
            }
        } else {
            self.nick = prefix
            self.user = nil
            self.host = nil
        }
    }

    var prefix: String {
        var result = ":\(nick)"
        if let user = user {
            result += "!\(user)"
        }
        if let host = host {
            result += "@\(host)"
        }
        return result
    }
}

struct IRCTags: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    typealias Key = String
    typealias Value = String

    private var storage: [String: String]

    init(dictionaryLiteral elements: (String, String)...) {
        var dict: [String: String] = [:]
        for (key, value) in elements {
            dict[key] = value
        }
        self.storage = dict
    }

    init(_ storage: [String: String] = [:]) {
        self.storage = storage
    }

    subscript(key: String) -> String? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    static func parse(_ tagString: String) -> IRCTags {
        var tags: [String: String] = [:]
        let tagPairs = tagString.split(separator: ";")
        for pair in tagPairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
                .replacingOccurrences(of: "\\:", with: ";")
                .replacingOccurrences(of: "\\s", with: " ")
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\r", with: "\r")
            tags[key] = value
        }
        return IRCTags(tags)
    }
}

struct IRCMessage: Sendable {
    let tags: IRCTags?
    let source: IRCUser?
    let command: String
    let parameters: [String]

    var nick: String? { source?.nick }

    init(tags: IRCTags? = nil, source: IRCUser? = nil, command: String, parameters: [String]) {
        self.tags = tags
        self.source = source
        self.command = command
        self.parameters = parameters
    }

    init(rawLine: String) {
        var tags: IRCTags? = nil
        var remaining = rawLine

        if remaining.hasPrefix("@") {
            if let spaceIndex = remaining.firstIndex(of: " ") {
                let tagsString = String(remaining[..<remaining.index(after: spaceIndex)].dropFirst())
                tags = IRCTags.parse(tagsString)
                remaining = String(remaining[remaining.index(after: spaceIndex)...])
            }
        }

        var source: IRCUser? = nil
        if remaining.hasPrefix(":") {
            if let spaceIndex = remaining.firstIndex(of: " ") {
                let sourceString = String(remaining[1..<remaining.index(after: spaceIndex)])
                source = IRCUser(prefix: sourceString)
                remaining = String(remaining[remaining.index(after: spaceIndex)...])
            }
        }

        remaining = remaining.trimmingCharacters(in: .whitespaces)

        let parts = remaining.split(separator: " ", maxSplits: 1)
        let command = parts.first.map(String.init) ?? ""
        let params = parts.count > 1 ? String(parts[1]) : ""

        var parameters: [String] = []
        if params.hasPrefix(":") {
            parameters = [String(params.dropFirst())]
        } else if !params.isEmpty {
            if let colonIndex = params.firstIndex(of: ":") {
                let prefix = String(params[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let trailing = String(params[params.index(after: colonIndex)...])
                parameters = prefix.split(separator: " ").map(String.init)
                parameters.append(trailing)
            } else {
                parameters = params.split(separator: " ").map(String.init)
            }
        }

        self.tags = tags
        self.source = source
        self.command = command
        self.parameters = parameters
    }

    var parameterString: String {
        parameters.joined(separator: " ")
    }

    func toString() -> String {
        var result = ""

        if let tags = tags, !tags.storage.isEmpty {
            let tagsString = tags.storage.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            result += "@\(tagsString) "
        }

        if let source = source {
            result += "\(source.prefix) "
        }

        result += command

        if !parameters.isEmpty {
            let leadingParams = parameters.dropLast()
            if !leadingParams.isEmpty {
                result += " " + leadingParams.joined(separator: " ")
            }
            if let last = parameters.last, !last.isEmpty {
                result += " :\(last)"
            }
        }

        return result
    }
}