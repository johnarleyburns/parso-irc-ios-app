import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let currentNick: String
    
    @State private var showActions = false
    
    private var isFromMe: Bool {
        message.isFromCurrentUser
    }
    
    private var bubbleColor: Color {
        if message.type == .action {
            return Color.theme.actionBubble.opacity(0.3)
        }
        
        if message.type == .join || message.type == .part || message.type == .quit || message.type == .nick || message.type == .topic {
            return Color.clear
        }
        
        return isFromMe ? Color.theme.sentBubble : Color.theme.receivedBubble
    }
    
    private var textColor: Color {
        if message.type == .action || message.type == .join || message.type == .part || message.type == .quit || message.type == .nick || message.type == .topic {
            return .secondary
        }
        
        return isFromMe ? .white : .primary
    }
    
    private var showAvatar: Bool {
        !isFromMe && !message.isGroupedWithPrevious && message.type == .message
    }
    
    private var isSystemMessage: Bool {
        message.type == .join || message.type == .part || message.type == .quit || message.type == .nick || message.type == .topic
    }
    
    var body: some View {
        if isSystemMessage {
            systemMessageView
        } else {
            regularMessageView
        }
    }
    
    private var systemMessageView: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.caption)
                .italic()
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            Spacer()
        }
        .padding(.vertical, 2)
    }
    
    private var regularMessageView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showAvatar {
                AvatarView(nick: message.sender, size: 32)
            } else if !isFromMe {
                Color.clear
                    .frame(width: 32, height: 32)
            }
            
            if isFromMe {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                if !message.isGroupedWithPrevious && !isFromMe {
                    Text(message.sender)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                messageContent
                
                messageFooter
            }
            
            if !isFromMe {
                Spacer(minLength: 40)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            Button {
                // Reply
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            
            Button {
                // Quote
            } label: {
                Label("Quote", systemImage: "text.quote")
            }
        }
    }
    
    @ViewBuilder
    private var messageContent: some View {
        if message.type == .action {
            Text("* \(message.sender) \(message.content)")
                .font(.body)
                .italic()
                .foregroundColor(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            Text(message.content)
                .font(.body)
                .foregroundColor(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .fill(bubbleColor)
                )
        }
    }
    
    private var bubbleCornerRadius: CGFloat {
        if message.isGroupedWithPrevious && message.isGroupedWithNext {
            return 4
        } else if message.isGroupedWithPrevious {
            return 4
        } else if message.isGroupedWithNext {
            return 18
        } else {
            return 18
        }
    }
    
    private var messageFooter: some View {
        HStack(spacing: 4) {
            Text(message.formattedTime)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if !message.reactions.isEmpty {
                HStack(spacing: 2) {
                    ForEach(message.reactions) { reaction in
                        Text(reaction.emoji)
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    let message1 = Message(
        channelId: "1",
        sender: "alice",
        content: "Hey everyone! How's it going?",
        timestamp: Date(),
        type: .message,
        isFromCurrentUser: false
    )
    
    let message2 = Message(
        channelId: "1",
        sender: "alice",
        content: "Anyone working on something cool?",
        timestamp: Date().addingTimeInterval(60),
        type: .message,
        isFromCurrentUser: false,
        previousSameSenderMessage: message1
    )
    
    let message3 = Message(
        channelId: "1",
        sender: "bob",
        content: "Just working on some code",
        timestamp: Date().addingTimeInterval(120),
        type: .message,
        isFromCurrentUser: true
    )
    
    VStack(spacing: 0) {
        MessageBubbleView(message: message1, currentNick: "bob")
        MessageBubbleView(message: message2, currentNick: "bob")
        MessageBubbleView(message: message3, currentNick: "bob")
    }
    .padding()
}