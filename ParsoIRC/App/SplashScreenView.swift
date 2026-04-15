import SwiftUI

struct SplashScreenView: View {
    @Binding var isPresented: Bool
    
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            Color.theme.sentBubble
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .scaleEffect(scale)
                
                Text("Parso IRC")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("IRC Made Simple")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1
                scale = 1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                }
            }
        }
    }
}

#Preview {
    SplashScreenView(isPresented: .constant(true))
}
