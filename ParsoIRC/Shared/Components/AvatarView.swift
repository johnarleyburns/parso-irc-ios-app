import SwiftUI

struct AvatarView: View {
    let nick: String
    let size: CGFloat
    let showBorder: Bool
    
    init(nick: String, size: CGFloat = 32, showBorder: Bool = true) {
        self.nick = nick
        self.size = size
        self.showBorder = showBorder
    }
    
    private var backgroundColor: Color {
        NickColorGenerator.color(for: nick)
    }
    
    private var initials: String {
        let firstChar = nick.prefix(1).uppercased()
        return firstChar
    }
    
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(backgroundColor)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color(uiColor: .systemBackground), lineWidth: showBorder ? 2 : 0)
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        AvatarView(nick: "john", size: 32)
        AvatarView(nick: "alice", size: 48)
        AvatarView(nick: "bob", size: 64)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}