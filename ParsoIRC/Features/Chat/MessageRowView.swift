import SwiftUI

// MARK: - Mention regex cache
//
// NSCache is thread-safe and handles memory pressure automatically.
// The regex for a given nick is compiled ONCE and reused for every
// message row render, eliminating the O(messages) regex compilations
// per SwiftUI layout pass that caused the main-thread hang / watchdog crash.
private let mentionRegexCache = NSCache<NSString, NSRegularExpression>()

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
    var isFailed: Bool = false

    /// Called when the user taps a nick anywhere in the row.
    var onTapNick: ((String) -> Void)? = nil
    /// Called when the user long-presses the bubble (context menu parent).
    var onLongPress: ((Message) -> Void)? = nil
    /// Called when the user taps the retry button on a failed outgoing message.
    var onRetry: ((Message) -> Void)? = nil

    // Appearance settings
    @AppStorage("messageFontSize") private var messageFontSize: Double = 15
    @AppStorage("messageDensity") private var messageDensity: String = "comfortable"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// System Dynamic Type category — used to scale `messageFontSize` so the
    /// message bubble body text responds to iOS Accessibility → Larger Text.
    @Environment(\.sizeCategory) private var sizeCategory

    private var verticalBubblePad: CGFloat { messageDensity == "compact" ? 6 : 8 }
    private var rowTopPad: CGFloat { grouped ? 1 : (messageDensity == "compact" ? 3 : 6) }

    /// Effective font size = user's slider base + Dynamic Type offset.
    ///
    /// The offset is the difference between the current `ContentSizeCategory`
    /// and `.large` (the system default), expressed in the same point-size
    /// increments Apple uses for the Body text style.  This means:
    ///   - Users at the system default see exactly the size they set in the slider.
    ///   - Users who enabled Larger Text get a proportional increase on top.
    ///   - Users who manually raised the slider AND enabled Larger Text get both.
    private var effectiveMessageFontSize: CGFloat {
        CGFloat(messageFontSize) + CGFloat(sizeCategory.messageBodyOffset)
    }

    private var isOutgoing: Bool { message.isFromCurrentUser }
    private var isSystem: Bool {
        switch message.type {
        case .join, .part, .quit, .nick, .mode, .topic, .kick, .ban, .invite, .system: return true
        default: return false
        }
    }
    private var isAction: Bool { message.type == .action }
    private var isNotice: Bool { message.type == .notice }

    // True when our nick appears as a whole word in the message (mention highlight).
    // Uses a cached NSRegularExpression — compiled once per unique nick, never per render.
    private var isMention: Bool {
        guard !isOutgoing && !currentNick.isEmpty else { return false }
        let cacheKey = currentNick.lowercased() as NSString
        let regex: NSRegularExpression
        if let cached = mentionRegexCache.object(forKey: cacheKey) {
            regex = cached
        } else {
            let escaped = NSRegularExpression.escapedPattern(for: currentNick)
            let pattern = "(?i)(?<![\\w])\\Q\(escaped)\\E(?![\\w])"
            guard let compiled = try? NSRegularExpression(pattern: pattern) else { return false }
            mentionRegexCache.setObject(compiled, forKey: cacheKey)
            regex = compiled
        }
        let range = NSRange(message.content.startIndex..., in: message.content)
        return regex.firstMatch(in: message.content, range: range) != nil
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
                           background: isFailed ? Color(.systemRed).opacity(0.85) : Color.theme.sentBubble,
                           foreground: .white,
                           corners: grouped ? [.topLeft, .bottomLeft, .bottomRight]
                                            : [.topLeft, .topRight, .bottomLeft, .bottomRight])
                HStack(spacing: 4) {
                    if isFailed {
                        Button {
                            onRetry?(message)
                        } label: {
                            Label("Not sent — tap to retry", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Message not sent. Tap to retry.")
                    } else if !grouped {
                        Text(message.timestamp.formattedTime())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.trailing, 4)
                    }
                }
            }
        }
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outgoingAccessibilityLabel)
        .accessibilityHint("Double-tap and hold for message options")
        .accessibilityAction(named: "Message options") { onLongPress?(message) }
        .onLongPressGesture { onLongPress?(message) }
    }

    private var outgoingAccessibilityLabel: String {
        let time = message.timestamp.formattedTime()
        if isFailed { return "Failed to send: \(message.content), at \(time)" }
        return "You, \(time): \(message.content)"
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
                .accessibilityLabel("View profile for \(message.sender)")
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
                    .accessibilityLabel("View profile for \(message.sender)")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(incomingAccessibilityLabel)
        .accessibilityHint("Double-tap and hold for message options")
        .accessibilityAction(named: "Message options") { onLongPress?(message) }
        .onLongPressGesture { onLongPress?(message) }
    }

    private var incomingAccessibilityLabel: String {
        let time = grouped ? "" : ", \(message.timestamp.formattedTime())"
        let mentionNote = isMention ? " (mentions you)" : ""
        return "\(message.sender)\(time): \(message.content)\(mentionNote)"
    }

    // MARK: - Shared bubble builder

    private func bubbleText(
        _ content: String,
        background: Color,
        foreground: Color,
        corners: UIRectCorner
    ) -> some View {
        Text(IRCTextFormatter.attributedString(from: content, foreground: foreground))
            .font(.system(size: effectiveMessageFontSize))
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
