import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var onSignUp: () -> Void
    var onSkip: () -> Void
    @Binding var showLogin: Bool
    
    @State private var currentPage = 0
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to Parso IRC",
            description: "Connect to IRC networks, join channels, and chat with communities around the world.",
            systemImage: "bubble.left.and.bubble.right.fill"
        ),
        OnboardingPage(
            title: "Join Communities",
            description: "Find channels on networks like Libera.Chat, connect with friends, and participate in discussions.",
            systemImage: "person.3.fill"
        ),
        OnboardingPage(
            title: "Stay Connected",
            description: "Chat in real-time, receive notifications, and never miss important messages.",
            systemImage: "bell.badge.fill"
        ),
        OnboardingPage(
            title: "Get Started",
            description: "Connect as a guest or create an account to save your chat history and preferences.",
            systemImage: "arrow.right.circle.fill"
        )
    ]
    
    var body: some View {
        ZStack {
            Color.theme.sentBubble
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") {
                        onSkip()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
                }
                
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(spacing: 24) {
                            Image(systemName: pages[index].systemImage)
                                .font(.system(size: 80))
                                .foregroundColor(.white)
                                .padding(.top, 60)
                            
                            Text(pages[index].title)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Text(pages[index].description)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            Spacer()
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                VStack(spacing: 20) {
                    PageIndicator(currentPage: currentPage, totalPages: pages.count)
                    
                    if currentPage == pages.count - 1 {
                        VStack(spacing: 12) {
                            Button {
                                onSignUp()
                            } label: {
                                Text("Sign Up")
                                    .font(.headline)
                                    .foregroundColor(Color.theme.sentBubble)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                            
                            Button {
                                showLogin = true
                            } label: {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 40)
                    } else {
                        Button {
                            if currentPage < pages.count - 1 {
                                withAnimation {
                                    currentPage += 1
                                }
                            }
                        } label: {
                            Text("Next")
                                .font(.headline)
                                .foregroundColor(Color.theme.sentBubble)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct OnboardingPage {
    let title: String
    let description: String
    let systemImage: String
}

struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview {
    OnboardingView(
        isPresented: .constant(true),
        onSignUp: {},
        onSkip: {},
        showLogin: .constant(false)
    )
}
