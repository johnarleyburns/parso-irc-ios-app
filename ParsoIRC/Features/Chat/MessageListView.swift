import SwiftUI

/// Scrollable list of messages, date separators, and a history-loading spinner.
///
/// Automatically scrolls to the bottom when new messages arrive and keeps
/// position when the user has scrolled up to read history.
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

    // ID of the bottom anchor
    private let bottomAnchorId = "BOTTOM_ANCHOR"

    var body: some View {
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
            // Always scroll to bottom when the view first appears with messages
            .onChange(of: viewModel.isLoadingHistory) { _, loading in
                if !loading {
                    scrollToBottom(proxy: proxy, animated: false)
                }
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
                onTapNick: onTapNick,
                onLongPress: { tapped in
                    contextMessage = tapped
                    showContextMenu = true
                    HapticManager.mediumImpact()
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
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
        isNearBottom = true
    }
}
