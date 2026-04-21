import SwiftUI

/// Scrollable list of messages, date separators, and a history-loading spinner.
///
/// Automatically scrolls to the bottom when new messages arrive and keeps
/// position when the user has scrolled up to read history.
/// Shows a jump-to-bottom button when the user has scrolled up.
struct MessageListView: View {
    @ObservedObject var viewModel: ChannelViewModel

    /// Called when the user taps a nick.
    var onTapNick: ((String) -> Void)? = nil

    // Long-press context menu state
    @State private var contextMessage: Message? = nil
    @State private var showContextMenu = false

    // Tracks whether the user is scrolled near the bottom
    @State private var isNearBottom = true
    @State private var scrollProxy: ScrollViewProxy? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // ID of the bottom anchor
    private let bottomAnchorId = "BOTTOM_ANCHOR"
    private let nearBottomSentinelId = "NEAR_BOTTOM_SENTINEL"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // History loading spinner at the top
                        if viewModel.isLoadingHistory {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                            .id("LOADING")
                        }

                        // Message rows
                        ForEach(viewModel.displayMessages) { item in
                            displayRow(for: item)
                                .id(item.id)
                        }

                        // Sentinel: when this is visible, user is near bottom
                        Color.clear.frame(height: 1)
                            .id(nearBottomSentinelId)
                            .onAppear  { isNearBottom = true  }
                            .onDisappear { isNearBottom = false }

                        // Invisible bottom anchor
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorId)
                    }
                    .padding(.bottom, 8)
                }
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy, animated: false)
                }
                // Scroll to bottom when new messages arrive (only if already near bottom)
                .onChange(of: viewModel.displayMessages.count) { _, _ in
                    if isNearBottom {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                // Always scroll to bottom when history finishes loading
                .onChange(of: viewModel.isLoadingHistory) { _, loading in
                    if !loading {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
            }

            // Jump-to-bottom button (appears when user has scrolled up)
            if !isNearBottom {
                Button {
                    if let proxy = scrollProxy {
                        scrollToBottom(proxy: proxy, animated: !reduceMotion)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.regularMaterial)
                            .frame(width: 40, height: 40)
                            .shadow(radius: 3)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                .animation(reduceMotion ? .none : .spring(duration: 0.25), value: isNearBottom)
                .accessibilityLabel("Scroll to latest message")
            }
        }
        .confirmationDialog(
            "Message",
            isPresented: $showContextMenu,
            titleVisibility: .hidden
        ) {
            if let msg = contextMessage {
                contextActions(for: msg)
            }
        }
    }

    // MARK: - Row dispatch

    @ViewBuilder
    private func displayRow(for item: DisplayMessage) -> some View {
        switch item {
        case .dateSeparator(let date):
            DateSeparatorView(date: date)

        case .message(let msg, let grouped):
            MessageRowView(
                message: msg,
                grouped: grouped,
                currentNick: viewModel.currentNick,
                isFailed: viewModel.failedMessageIds.contains(msg.id),
                onTapNick: onTapNick,
                onLongPress: { tapped in
                    contextMessage = tapped
                    showContextMenu = true
                    HapticManager.mediumImpact()
                },
                onRetry: { failedMsg in
                    viewModel.retrySend(message: failedMsg)
                }
            )
        }
    }

    // MARK: - Context menu actions

    @ViewBuilder
    private func contextActions(for msg: Message) -> some View {
        Button {
            UIPasteboard.general.string = msg.content
            HapticManager.selectionFeedback()
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }

        Button {
            // Mention: pass nick back so InputBarView can pre-fill it
            onTapNick?(msg.sender)
        } label: {
            Label("Mention \(msg.sender)", systemImage: "at")
        }

        Button(role: .cancel) {} label: {
            Text("Dismiss")
        }
    }

    // MARK: - Scroll helpers

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let shouldAnimate = animated && !reduceMotion
        if shouldAnimate {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
        isNearBottom = true
    }
}
