import SwiftUI

struct TypingIndicatorView: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animating ? -4 : 4)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.theme.receivedBubble)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            animating = true
        }
    }
}

#Preview {
    TypingIndicatorView()
        .padding()
}