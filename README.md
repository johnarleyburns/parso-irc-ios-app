# Parso IRC

An award-winning iOS IRC client written in Swift, following the latest iOS Human Interface Guidelines.

## Features

- **Multi-Network Support**: Pre-configured with top 10 IRC networks
  - Libera.Chat (primary)
  - OFTC
  - hackint
  - IRCnet
  - Undernet
  - Rizon
  - QuakeNet
  - DALnet
  - EFnet
  - Snoonet

- **Modern UI/UX**:
  - iOS Messages app-inspired chat interface
  - Dynamic colors (dark/light/system)
  - Message grouping (same sender, <5 min)
  - Tapback reactions
  - Typing indicators
  - Date separators

- **IRC Features**:
  - Full IRC command support (/nick, /join, /part, etc.)
  - SASL authentication
  - TLS/SSL connections
  - Auto-reconnect
  - Channel member list

- **Offline Storage**:
  - 30-day message retention
  - Up to 1000 messages per channel

## Requirements

- iOS 16.0+
- Xcode 15.4+
- Swift 5.9+

## Building

### Local Development (macOS with Xcode)

```bash
# Install XcodeGen
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open ParsoIRC.xcodeproj
```

### GitHub Actions (CI/CD)

The project includes automated build workflows. To build:

1. Go to **Actions** tab in GitHub
2. Run the **iOS Build** workflow
3. Download the build artifact

## Distribution

### TestFlight (Requires Apple Developer Account)

1. Set up GitHub secrets:
   - `APPLE_ID`: Your Apple ID email
   - `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password
   - `TEAM_ID`: Your Apple Developer Team ID

2. Create a release on GitHub
3. The workflow will build and upload to TestFlight

### Simulator Testing

Builds can be tested on the iOS Simulator without code signing:
```bash
xcodebuild -project ParsoIRC.xcodeproj \
  -scheme ParsoIRC \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

## Project Structure

```
ParsoIRC/
├── App/                    # App entry point
├── Core/
│   ├── IRC/               # IRC client manager
│   ├── Storage/           # SQLite database
│   └── Models/            # Data models
├── Features/
│   ├── Servers/           # Server list UI
│   ├── Conversations/     # Channel list UI
│   ├── Chat/              # Chat view UI
│   ├── Members/           # Member list UI
│   └── Settings/          # Settings UI
├── Shared/
│   ├── Components/        # Reusable components
│   ├── Extensions/        # Swift extensions
│   └── Utilities/         # Helper classes
└── Resources/             # Assets
```

## Dependencies

- **IRCKit** (FuelRats/IRCKit): IRC protocol implementation
- **SQLite.swift**: Local database storage

## License

MIT License