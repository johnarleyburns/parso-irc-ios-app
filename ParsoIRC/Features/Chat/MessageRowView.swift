import SwiftUI

/// Renders a single row in the message list.
///
/// Handles four visual styles:
/// - **System** (join/part/quit/nick/mode/topic/kick): centered italic text, no bubble.
/// - **Action** (`/me`): italic inline text with colored nick, no bubble.
/// - **Outgoing** (isFromCurrentUser): right-aligned blue bubble.
/// - **Incoming**: left-aligned gray bubble with nick header (collapsed when grouped).
///
/// `grouped` suppresses the avatar and nick header for consecutive messages
/// from the same sender within 5 minutes, giving a "thread" feel.
struct MessageRowView: View {
    let message: Message
    let grouped: Bool
    let currentNick: String

    /// Called when the user taps a nick anywhere in the row.
    var onTapNick: ((String) -> Void)? = nil
    /// Called when the user long-presses the bubble (context menu parent).
    var onLongPress: ((Message) -> Void)? = nil

    // Appearance settings
    @AppStorage("messageFontSize") private var messageFontSize: Double = 15
    @AppStorage("messageDensity") private var messageDensity: String = "comfortable"

    private var verticalBubblePad: CGFloat { messageDensity == "compact" ? 6 : 8 }
    private var rowTopPad: CGFloat { grouped ? 1 : (messageDensity == "compact" ? 3 : 6) }

    private var isOutgoing: Bool { message.isFromCurrentUser }
    private var isSystem: Bool {
        switch message.type {
        case .join, .part, .quit, .nick, .mode, .topic, .kick, .ban, .invite, .system: return true
        default: return false
        }
    }
    private var isAction: Bool { message.type == .action }
    private var isNotice: Bool { message.type == .notice }

    // True when our nick appears as a whole word in the message (mention highlight)
    private var isMention: Bool {
        guard !isOutgoing && !currentNick.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: currentNick)
        // Match nick as a whole word, optionally followed by : or ,
        let pattern = "(?i)(?<![\\w])\\Q\(escaped)\\E(?![\\w])"
        return message.content.range(of: pattern, options: .regularExpression) != nil
    }

    var body: some View {
        Group {
            if isSystem {
                systemRow
            } else if isAction {
                actionRow
            } else if isOutgoing {
                outgoingRow
            } else {
                incomingRow
            }
        }
        // Tighter spacing when grouped, generous when not
        .padding(.top, rowTopPad)
        .padding(.bottom, 1)
    }

    // MARK: - System row

    private var systemRow: some View {
        Text(message.content)
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
            .multilineTextAlignment(.center)
            .padding(.vertical, 2)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Action row  (* nick does something)

    private var actionRow: some View {
        HStack(spacing: 4) {
            Text("*")
                .font(.subheadline)
                .foregroundStyle(NickColorGenerator.color(for: message.sender))
                .fontWeight(.semibold)
            Button {
                onTapNick?(message.sender)
            } label: {
                Text(message.sender)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(NickColorGenerator.color(for: message.sender))
            }
            .buttonStyle(.plain)
            Text(message.content)
                .font(.subheadline)
                .italic()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Outgoing bubble

    private var outgoingRow: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 2) {
                bubbleText(message.content,
                           background: Color.theme.sentBubble,
                           foreground: .white,
                           corners: grouped ? [.topLeft, .bottomLeft, .bottomRight]
                                            : [.topLeft, .topRight, .bottomLeft, .bottomRight])
                if !grouped {
                    Text(message.timestamp.formattedTime())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 4)
                }
            }
        }
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .onLongPressGesture { onLongPress?(message) }
    }

    // MARK: - Incoming bubble

    private var incomingRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Avatar (or spacer when grouped)
            if grouped {
                Spacer().frame(width: 32)
            } else {
                Button { onTapNick?(message.sender) } label: {
                    AvatarView(nick: message.sender, size: 32, showBorder: false)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Nick header (hidden when grouped)
                if !grouped {
                    Button { onTapNick?(message.sender) } label: {
                        Text(message.sender)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(NickColorGenerator.color(for: message.sender))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }

                // Bubble
                bubbleText(
                    isNotice ? "[\(message.sender)] \(message.content)" : message.content,
                    background: isMention
                        ? Color(.systemYellow).opacity(0.18)
                        : Color.theme.receivedBubble,
                    foreground: .primary,
                    corners: grouped ? [.topRight, .bottomLeft, .bottomRight]
                                     : [.topLeft, .topRight, .bottomRight]
                )
                .overlay(
                    // Mention accent stripe on left edge
                    isMention
                        ? RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemYellow))
                            .frame(width: 3)
                            .padding(.vertical, 4)
                            .frame(maxHeight: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                        : nil
                )

                if !grouped {
                    Text(message.timestamp.formattedTime())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }

            Spacer(minLength: 60)
        }
        .padding(.leading, 12)
        .contentShape(Rectangle())
        .onLongPressGesture { onLongPress?(message) }
    }

    // MARK: - Shared bubble builder

    private func bubbleText(
        _ content: String,
        background: Color,
        foreground: Color,
        corners: UIRectCorner
    ) -> some View {
        Text(IRCTextFormatter.attributedString(from: content, foreground: foreground))
            .font(.system(size: messageFontSize))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, verticalBubblePad)
            .background(
                BubbleShape(corners: corners)
                    .fill(background)
            )
            .textSelection(.enabled)
    }
}

// MARK: - BubbleShape

/// A rounded-rectangle where only specified corners are rounded.
/// The rounded corners use a 16pt radius; the flat corners use 4pt
/// so the "thread stack" looks cohesive without sharp 90° angles.
struct BubbleShape: Shape {
    let corners: UIRectCorner
    var radius: CGFloat = 16
    var minRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let tl: CGFloat = corners.contains(.topLeft)     ? radius : minRadius
        let tr: CGFloat = corners.contains(.topRight)    ? radius : minRadius
        let br: CGFloat = corners.contains(.bottomRight) ? radius : minRadius
        let bl: CGFloat = corners.contains(.bottomLeft)  ? radius : minRadius

        var path = Path()
        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: rect.width - tr, y: 0))
        path.addArc(center: CGPoint(x: rect.width - tr, y: tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - br))
        path.addArc(center: CGPoint(x: rect.width - br, y: rect.height - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: bl, y: rect.height))
        path.addArc(center: CGPoint(x: bl, y: rect.height - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

#Preview {
    let base = Date()
    return ScrollView {
        VStack(spacing: 0) {
            // System
            MessageRowView(
                message: Message(channelId: "c", sender: "alice", content: "alice joined #linux", type: .join),
                grouped: false, currentNick: "me"
            )
            // Incoming ungrouped
            MessageRowView(
                message: Message(channelId: "c", sender: "alice", content: "Hello everyone!", timestamp: base),
                grouped: false, currentNick: "me"
            )
            // Incoming grouped
            MessageRowView(
                message: Message(channelId: "c", sender: "alice", content: "How's it going?",
                                 timestamp: base.addingTimeInterval(30)),
                grouped: true, currentNick: "me"
            )
            // Mention
            MessageRowView(
                message: Message(channelId: "c", sender: "bob", content: "Hey me, check this out!"),
                grouped: false, currentNick: "me"
            )
            // Outgoing
            MessageRowView(
                message: Message(channelId: "c", sender: "me", content: "Hey all!", isFromCurrentUser: true),
                grouped: false, currentNick: "me"
            )
            // Action
            MessageRowView(
                message: Message(channelId: "c", sender: "alice", content: "waves at everyone", type: .action),
                grouped: false, currentNick: "me"
            )
        }
        .padding(.vertical)
    }
    .background(Color(.systemGroupedBackground))
}
