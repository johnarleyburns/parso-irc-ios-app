# Parso IRC - Award-Winning iOS IRC Client

## Implementation Plan (Agentic Coding)

---

## 1. Project Overview

- **App Name:** Parso IRC
- **Bundle ID:** `com.parso.irc`
- **Min iOS:** 16.0
- **UI Framework:** SwiftUI
- **Architecture:** MVVM + Repository Pattern

---

## 2. Pre-Configured Networks (Top 10)

### Network 1: Libera.Chat (Primary)
- **Host:** `irc.libera.chat` | **Port:** 6697 | **TLS:** ✅
- **Default Channels:** #libera, #linux, #bash, #systemd, #kernel, #archlinux, #debian, #rust, #python, #security, #ubuntu, #gentoo, #fedora, #lxc

### Network 2: OFTC
- **Host:** `irc.oftc.net` | **Port:** 6697 | **TLS:** ✅

### Network 3: hackint
- **Host:** `irc.hackint.org` | **Port:** 6697 | **TLS:** ✅

### Network 4: IRCnet
- **Host:** `ircnet.ircchat.de` | **Port:** 6667

### Network 5: Undernet
- **Host:** `irc.undernet.org` | **Port:** 6667

### Network 6: Rizon
- **Host:** `irc.rizon.net` | **Port:** 6697 | **TLS:** ✅

### Network 7: QuakeNet
- **Host:** `irc.quakenet.org` | **Port:** 6667

### Network 8: DALnet
- **Host:** `irc.dal.net` | **Port:** 6667

### Network 9: EFnet
- **Host:** `irc.efnet.org` | **Port:** 6667

### Network 10: Snoonet
- **Host:** `irc.snoonet.org` | **Port:** 6697 | **TLS:** ✅

---

## 3. UI/UX Design Specification

### 3.1 Color Palette (iOS 18 Dynamic)

```
┌─────────────────────────────────────────────────────────────┐
│                    COLORS                                    │
├─────────────────────────────────────────────────────────────┤
│ Background:                                                 │
│   - Primary: System background (adaptive)                   │
│   - Secondary: #1C1C1E (dark) / #F2F2F7 (light)            │
│   - Tertiary: #2C2C2E (dark) / #FFFFFF (light)             │
│                                                              │
│ Accent Colors:                                              │
│   - Primary: #0A84FF (iOS Blue)                            │
│   - Sent Bubble: #0A84FF                                    │
│   - Received Bubble: #3A3A3C (dark) / #E5E5EA (light)      │
│   - Action (/me): #5856D6 (Purple, italic)                 │
│   - System: #8E8E93 (Gray 2), italic                       │
│                                                              │
│ Status:                                                     │
│   - Online: #30D158 (Green)                                │
│   - Away: #FF9F0A (Orange)                                  │
│   - Offline: #8E8E93 (Gray)                                 │
│   - Error: #FF453A (Red)                                   │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Typography (SF Pro - System Font)

```
┌─────────────────────────────────────────────────────────────┐
│                    TYPOGRAPHY                               │
├─────────────────────────────────────────────────────────────┤
│ Navigation Title:   .largeTitle - 34pt Bold                 │
│ Section Header:     .headline - 17pt Semibold               │
│ Channel Name:       .body - 17pt Medium                     │
│ Message Text:       .body - 17pt Regular                    │
│ Timestamp:          .caption1 - 12pt Regular (50% opacity)  │
│ Username:           .subheadline - 15pt Semibold            │
│ Input Field:        .body - 17pt Regular                    │
│ Tab Bar:            .tabular - 10pt Medium                  │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Screen Structure

```
┌─────────────────────────────────────────────────────────┐
│                    TabView (2 tabs)                     │
├─────────────────────┬─────────────────────────────────────┤
│  Servers            │  Conversations                      │
│  (List)             │  (All channels & DMs)               │
├─────────────────────┴─────────────────────────────────────┤
│                                                      │
│              Main Content Area                        │
│         (Chat View / Channel Details)                  │
│                                                      │
├─────────────────────────────────────────────────────────┤
│  Input Bar: [TextField] [Send Button]                 │
└─────────────────────────────────────────────────────────┘
```

### 3.4 Chat UI - Award-Winning Design

#### Message Bubble Specs
```
┌─────────────────────────────────────────────────────────┐
│                 MESSAGE BUBBLE SPECS                    │
├─────────────────────────────────────────────────────────┤
│ Corner Radius:     18pt (standard)                      │
│                   4pt (stacked, for grouped messages)  │
│                   18pt (first/last in group)          │
│ Max Width:        75% of screen width                  │
│ Min Width:        60pt                                 │
│ Padding:          12pt horizontal, 8pt vertical        │
│                                                              │
│ Avatar Size:      32x32 (shown on received messages)    │
│ Avatar Position: 8pt to left of bubble, bottom-aligned │
│                                                              │
│ Grouping:         Same sender within 5 minutes =      │
│                   continuous bubble (no avatar)        │
│                                                              │
│ Tail:             iOS 17+ style (subtle curve)          │
│                   Only on first/last message in group  │
└─────────────────────────────────────────────────────────┘
```

#### Date Separators (Sticky Headers)
- **Today:** "Today" centered
- **Yesterday:** "Yesterday" centered
- **Past:** "March 15, 2024" centered
- **Animation:** Fade in on scroll

#### Input Bar Specs
```
┌─────────────────────────────────────────────────────────┐
│                    INPUT BAR SPECS                      │
├─────────────────────────────────────────────────────────┤
│ Min Height:      44pt (single line)                     │
│ Max Height:      120pt (5 lines, then scroll)          │
│ Corner Radius:   22pt (rounded pill)                   │
│ Background:      #3A3A3C (dark) / #E5E5EA (light)      │
│                                                              │
│ Left:            Channel selector (if in multiple)     │
│ Center:          TextField with placeholder            │
│ Right:           Send button (SF Symbol: arrow.up.circle.fill) │
│                                                              │
│ Placeholder:     "Message #channel" or "Message"       │
│ Expand Trigger:  2+ lines of text                      │
└─────────────────────────────────────────────────────────┘
```

### 3.5 Animations & Interactions

| Action | Animation | Duration | Curve |
|--------|-----------|----------|-------|
| Message appear | Scale 0.95→1.0 + Opacity 0→1 | 200ms | Spring |
| Send message | Slide up from bottom | 150ms | easeOut |
| Typing indicator | 3-dot bounce loop | 600ms | easeInOut |
| Tab switch | Cross-dissolve | 250ms | easeInOut |
| Sheet present | iOS default spring | - | spring |
| Pull to refresh | Standard iOS | - | - |
| Long-press menu | Scale 0.95 + blur backdrop | 200ms | spring |

### 3.6 Haptic Feedback

| Action | Haptic |
|--------|--------|
| Send message | Light impact |
| Connect success | Success |
| Connect fail | Error |
| Tapback react | Light impact |
| Pull to refresh | Medium impact |

---

## 4. Feature Specification

### 4.1 Power User IRC Commands (All Supported)

| Command | Implementation | GUI Alternative |
|---------|---------------|-----------------|
| `/nick <new>` | Full parser | Settings → Account |
| `/join #chan` | Full parser | + button, autocomplete |
| `/part [chan]` | Full parser | Swipe → Leave |
| `/msg <nick> <text>` | Full parser | Tap user → DM |
| `/topic [new]` | Full parser | Channel info sheet |
| `/mode +/-flags` | Full parser | (operators only) |
| `/whois <nick>` | Full parser | Tap username |
| `/kick <nick>` | Full parser | (operators only) |
| `/ban <nick>` | Full parser | (operators only) |
| `/invite <nick> #chan` | Full parser | - |
| `/away [message]` | Full parser | Auto (idle) |
| `/quit [message]` | Full parser | Server disconnect |
| `/list [pattern]` | Full parser | Channel browser |
| `/away` | Full parser | Settings toggle |
| `/me <action>` | Full parser | Shows as italic action |

**Command Palette:** Type `/` to show autocomplete dropdown

### 4.2 Graphical Features (No Commands Required)

- ✅ Server management (add/edit/delete/connect)
- ✅ Pre-populated network templates (10 networks)
- ✅ Auto-join channels on connect
- ✅ Visual channel list (all servers)
- ✅ Visual member list with search
- ✅ Per-channel notification settings (All/Mentions/None)
- ✅ Message search within channel
- ✅ Typing indicators (client-to-client)
- ✅ Nickname color by hash
- ✅ Dark/Light/System theme support
- ✅ Offline message storage (30 days/1000 msgs)
- ✅ Connection auto-reconnect
- ✅ SASL authentication (PLAIN/SCRAM-SHA-256)
- ✅ TLS/SSL connections

### 4.3 IRCv3 Features

- [x] SASL PLAIN
- [x] SASL SCRAM-SHA-256
- [x] TLS/SSL
- [x] Capability negotiation
- [x] Message tags (msgid)
- [x] Server-time (timestamps)
- [x] Echo-message
- [x] Away notifications
- [x] Extended-join (user info on join)

---

## 5. Data Architecture

### 5.1 SQLite Schema

```sql
-- Servers
CREATE TABLE servers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER DEFAULT 6697,
    ssl INTEGER DEFAULT 1,
    nickname TEXT,
    realname TEXT,
    password TEXT,
    sasl_enabled INTEGER DEFAULT 0,
    sasl_mechanism TEXT DEFAULT 'PLAIN',
    auto_connect INTEGER DEFAULT 1,
    created_at TEXT,
    last_connected TEXT
);

-- Channels
CREATE TABLE channels (
    id TEXT PRIMARY KEY,
    server_id TEXT NOT NULL,
    name TEXT NOT NULL,
    topic TEXT,
    is_muted INTEGER DEFAULT 0,
    notifications TEXT DEFAULT 'normal',
    last_read_message_id TEXT,
    joined_at TEXT,
    UNIQUE(server_id, name)
);

-- Messages
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    channel_id TEXT NOT NULL,
    sender TEXT,
    sender_host TEXT,
    content TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    type TEXT DEFAULT 'message',
    is_read INTEGER DEFAULT 0,
    created_at TEXT
);

-- Settings
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Indexes
CREATE INDEX idx_messages_channel_time ON messages(channel_id, timestamp DESC);
CREATE INDEX idx_messages_limit ON messages(channel_id, timestamp);
```

### 5.2 Storage Rules

- **Retention:** 30 days AND 1000 messages per channel (whichever first)
- **Background cleanup:** On app launch
- **Message deletion:** FIFO when limit reached

---

## 6. File Structure

```
ParsoIRC/
├── App/
│   ├── ParsoIRCApp.swift              # @main entry
│   └── ContentView.swift              # TabView container
├── Core/
│   ├── IRC/
│   │   ├── IRCClientManager.swift     # Connection pool singleton
│   │   ├── IRCMessage+Extensions.swift
│   │   ├── IRCCommandParser.swift
│   │   └── IRCEvents.swift
│   ├── Storage/
│   │   ├── DatabaseManager.swift       # SQLite.swift wrapper
│   │   ├── ServerRepository.swift
│   │   ├── ChannelRepository.swift
│   │   └── MessageRepository.swift
│   └── Models/
│       ├── Server.swift
│       ├── Channel.swift
│       ├── Message.swift
│       └── IRCTypes.swift
├── Features/
│   ├── Servers/
│   │   ├── ServerListView.swift
│   │   ├── ServerListViewModel.swift
│   │   ├── AddServerSheet.swift
│   │   └── ServerCell.swift
│   ├── Conversations/
│   │   ├── ConversationListView.swift
│   │   ├── ConversationListViewModel.swift
│   │   └── ConversationCell.swift
│   ├── Chat/
│   │   ├── ChatView.swift
│   │   ├── ChatViewModel.swift
│   │   ├── MessageBubbleView.swift
│   │   ├── MessageListView.swift
│   │   ├── InputBarView.swift
│   │   ├── TypingIndicatorView.swift
│   │   ├── CommandPaletteView.swift
│   │   ├── TapbackPicker.swift
│   │   └── DateSeparatorView.swift
│   ├── Members/
│   │   ├── MemberListView.swift
│   │   ├── MemberListViewModel.swift
│   │   └── MemberCell.swift
│   └── Settings/
│       ├── SettingsView.swift
│       ├── SettingsViewModel.swift
│       └── AppearanceSettingsView.swift
├── Shared/
│   ├── Components/
│   │   ├── AvatarView.swift
│   │   ├── BadgeView.swift
│   │   ├── ConnectionStatusView.swift
│   │   └── LoadingView.swift
│   ├── Extensions/
│   │   ├── Color+Theme.swift
│   │   ├── Date+Formatting.swift
│   │   ├── String+IRC.swift
│   │   └── View+Extensions.swift
│   └── Utilities/
│       ├── HapticManager.swift
│       ├── NickColorGenerator.swift
│       └── Constants.swift
└── Resources/
    ├── Assets.xcassets
    └── Preview Content/
```

---

## 7. Dependencies (Swift Package Manager)

| Package | Version | Purpose |
|---------|---------|---------|
| FuelRats/IRCKit | 0.16.0 | IRC protocol (async/await) |
| SQLite.swift | 0.15.0 | Local database |

---

## 8. GitHub Actions CI/CD

```yaml
name: iOS Build

on:
  push:
    branches: [main]
  release:
    types: [created]

jobs:
  build:
    runs-on: macos-15
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Xcode
        uses: actions/setup-xcode@v1
        with:
          xcode-version: '15.4'
      
      - name: Install XcodeGen
        run: brew install xcodegen
      
      - name: Build
        run: |
          xcodebuild -project ParsoIRC.xcodeproj \
            -scheme ParsoIRC \
            -configuration Debug \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            build
      
      - name: Test
        run: |
          xcodebuild test -project ParsoIRC.xcodeproj \
            -scheme ParsoIRC \
            -destination 'platform=iOS Simulator,name=iPhone 16'
      
      - name: Upload to TestFlight
        if: github.event_name == 'release'
        run: |
          # Uses APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, TEAM_ID secrets
          xcodebuild -exportArchive \
            -archivePath build/ParsoIRC.xcarchive \
            -exportPath output
          altool --upload-app -f output/ParsoIRC.ipa
```

---

## 9. Implementation Order

### Phase 1: Foundation (Agent Tasks 1-4)
1. Create `project.yml` for XcodeGen
2. Create folder structure and placeholder files
3. Set up Swift Package dependencies in project.yml
4. Implement data models (Server, Channel, Message)

### Phase 2: Storage Layer (Agent Tasks 5-8)
5. Implement `DatabaseManager` with SQLite.swift
6. Implement repositories (Server, Channel, Message)
7. Add pre-populated network templates
8. Add offline storage rules (30 days/1000 msgs)

### Phase 3: IRC Core (Agent Tasks 9-12)
9. Implement `IRCClientManager` singleton
10. Handle connection, SASL, reconnection
11. Implement command parser (/nick, /join, etc.)
12. Handle IRC events (join, part, quit, nick, mode)

### Phase 4: UI - Navigation (Agent Tasks 13-14)
13. Create main TabView with Server List + Conversations
14. Implement server list with add/edit/delete

### Phase 5: UI - Chat (Agent Tasks 15-20)
15. Implement ChatView with message list
16. Create MessageBubbleView (iOS Messages style)
17. Implement InputBarView with expandable text
18. Add command palette on "/" typing
19. Add typing indicator view
20. Add date separators

### Phase 6: UI - Polish (Agent Tasks 21-24)
21. Implement tapbacks/reactions picker
22. Create member list view
23. Add settings screen
24. Implement dark/light/system themes

### Phase 7: Features (Agent Tasks 25-28)
25. Add connection status indicators
26. Implement auto-reconnect
27. Add notification settings
28. Message search functionality

### Phase 8: Testing & Deployment (Agent Tasks 29-30)
29. Add unit tests
30. Set up GitHub Actions CI/CD

---

## 10. Acceptance Criteria

- [ ] Connects to Libera.Chat with TLS on port 6697
- [ ] Pre-populated with 10 networks
- [ ] Auto-joins default channels on connect
- [ ] Send/receive messages in real-time
- [ ] /nick and /join commands work (full IRC command support)
- [ ] Message bubbles match iOS Messages app design (18pt corners, 75% width, avatar grouping)
- [ ] Offline storage works (30 days / 1000 messages per channel)
- [ ] iOS 18-style UI with dynamic colors, dark mode support
- [ ] Build passes on iOS Simulator via XcodeGen
- [ ] GitHub Actions CI/CD configured
- [ ] TestFlight upload ready (with Apple Developer credentials)

---

**Start Implementation Now**