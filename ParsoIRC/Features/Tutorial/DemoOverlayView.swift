import SwiftUI

/// Demo mode step tracker.
///
/// Steps 0-4 correspond to coach-mark tooltips shown in the sidebar and chat.
/// Step 99 = dismissed (user tapped "Skip").
enum DemoStep: Int {
    case expandServer   = 0
    case openChannel    = 1
    case sendMessage    = 2
    case longPress      = 3
    case useOptions     = 4
    case done           = 99

    static let userDefaultsKey = "demoStep"

    static func current() -> DemoStep {
        let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return DemoStep(rawValue: raw) ?? .expandServer
    }

    func advance() {
        let next = self.rawValue + 1
        UserDefaults.standard.set(next, forKey: DemoStep.userDefaultsKey)
    }

    func dismiss() {
        UserDefaults.standard.set(DemoStep.done.rawValue, forKey: DemoStep.userDefaultsKey)
    }
}

/// A floating pill-shaped coach-mark overlay for demo mode.
///
/// Pass the `step` this overlay should be visible for.  It renders itself only
/// when `AppState.isDemoMode` is true AND the current demo step matches.
struct DemoOverlayView: View {
    let step: DemoStep
    let arrowEdge: Edge
    let text: String

    @AppStorage(DemoStep.userDefaultsKey) private var currentStepRaw: Int = 0
    @EnvironmentObject private var appState: AppState

    private var isVisible: Bool {
        appState.isDemoMode && currentStepRaw == step.rawValue
    }

    var body: some View {
        if isVisible {
            pillTooltip
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal:   .opacity
                ))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isVisible)
                .zIndex(100)
        }
    }

    // MARK: - Pill tooltip

    private var pillTooltip: some View {
        VStack(spacing: 4) {
            if arrowEdge == .bottom {
                arrowShape
            }

            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                    .font(.body)
                    .foregroundStyle(.white)

                Text(text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    DemoStep.done.advance()   // sets to 99 = dismissed
                    UserDefaults.standard.set(DemoStep.done.rawValue,
                                              forKey: DemoStep.userDefaultsKey)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(4)
                        .background(Circle().fill(.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip tutorial")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            )

            if arrowEdge == .top {
                arrowShape
            }
        }
        .padding(.horizontal, 16)
    }

    private var arrowShape: some View {
        Image(systemName: arrowEdge == .top ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 32)
    }
}

// MARK: - Convenience step factories

extension DemoOverlayView {
    /// Shown in ServerSidebarView when the user hasn't expanded the demo server yet.
    static func expandServer() -> DemoOverlayView {
        DemoOverlayView(
            step: .expandServer,
            arrowEdge: .top,
            text: "Tap \"Parso Demo Server\" to expand it"
        )
    }

    /// Shown when the server is expanded but no channel has been opened.
    static func openChannel() -> DemoOverlayView {
        DemoOverlayView(
            step: .openChannel,
            arrowEdge: .top,
            text: "Tap #demo to open the channel"
        )
    }

    /// Shown inside ChatView before the user sends their first message.
    static func sendMessage() -> DemoOverlayView {
        DemoOverlayView(
            step: .sendMessage,
            arrowEdge: .bottom,
            text: "Type a message and tap Send"
        )
    }

    /// Shown after the user sends a message, prompting them to long-press.
    static func longPress() -> DemoOverlayView {
        DemoOverlayView(
            step: .longPress,
            arrowEdge: .bottom,
            text: "Long-press any message to see options"
        )
    }

    /// Shown when the context menu appears.
    static func useOptions() -> DemoOverlayView {
        DemoOverlayView(
            step: .useOptions,
            arrowEdge: .bottom,
            text: "Try Report, Delete, or Block User"
        )
    }
}

#Preview {
    VStack {
        DemoOverlayView.expandServer()
        DemoOverlayView.sendMessage()
    }
    .environmentObject(AppState.shared)
    .padding()
}
