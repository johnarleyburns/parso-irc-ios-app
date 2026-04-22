import SwiftUI

/// Scrollable list of messages, date separators, and a history-loading spinner.
///
/// Automatically scrolls to the bottom when new messages arrive and keeps
/// position when the user has scrolled up to read history.
/// Shows a jump-to-bottom button when the user has scrolled up.
struct MessageListView: View {
    @ObservedObject var viewModel: ChannelViewModel

    /// Channel name — used in violation reports.
    var channelName: String = ""

    /// Called when the user taps a nick.
    var onTapNick: ((String) -> Void)? = nil

    // Long-press context menu state
    @State private var contextMessage: Message? = nil
    @State private var showContextMenu = false
    @State private var showBlockConfirm = false
    @State private var showReportFallbackAlert = false
    @State private var reportFallbackText = ""

    @EnvironmentObject private var appState: AppState

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
        // Context menu (long-press)
        .confirmationDialog(
            "Message Options",
            isPresented: $showContextMenu,
            titleVisibility: .hidden
        ) {
            if let msg = contextMessage {
                contextActions(for: msg)
            }
        }
        // Block user confirmation
        .alert(
            "Block User",
            isPresented: $showBlockConfirm,
            presenting: contextMessage
        ) { msg in
            Button("Block \(msg.sender)", role: .destructive) {
                viewModel.blockSender(nick: msg.sender)
                HapticManager.mediumImpact()
            }
            Button("Cancel", role: .cancel) {}
        } message: { msg in
            Text("Messages from \(msg.sender) will be hidden. You can unblock them in Settings > Blocked Users.")
        }
        // Report fallback (no Mail app)
        .alert("Report Copied", isPresented: $showReportFallbackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The violation report has been copied to your clipboard. Please email it to info@parso.guru.")
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
        let isSystem = msg.type == .join || msg.type == .part || msg.type == .quit
            || msg.type == .nick || msg.type == .mode || msg.type == .topic
            || msg.type == .kick || msg.type == .ban || msg.type == .invite
            || msg.type == .system
        let isOwn = msg.isFromCurrentUser

        // Copy — always available for non-system messages
        if !isSystem {
            Button {
                UIPasteboard.general.string = msg.content
                HapticManager.selectionFeedback()
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }

        // Mention — only for incoming non-system messages
        if !isSystem && !isOwn {
            Button {
                onTapNick?(msg.sender)
            } label: {
                Label("Mention \(msg.sender)", systemImage: "at")
            }
        }

        // Report for Violations — all non-system messages
        if !isSystem {
            Button {
                reportMessage(msg)
            } label: {
                Label("Report for Violations", systemImage: "exclamationmark.shield")
            }
        }

        // Delete (local hide) — all non-system messages (both own and incoming)
        if !isSystem {
            Button(role: .destructive) {
                viewModel.locallyDeleteMessage(id: msg.id)
                HapticManager.mediumImpact()
            } label: {
                Label("Delete Message", systemImage: "trash")
            }
        }

        // Block User — incoming non-system messages only (can't block yourself)
        if !isSystem && !isOwn {
            Button(role: .destructive) {
                showBlockConfirm = true
            } label: {
                Label("Block \(msg.sender)", systemImage: "person.fill.xmark")
            }
        }

        Button(role: .cancel) {} label: {
            Text("Dismiss")
        }
    }

    // MARK: - Report helper

    private func reportMessage(_ msg: Message) {
        let dateStr = msg.timestamp.formatted(date: .abbreviated, time: .shortened)
        let body = """
Violation Report — Parso IRC

Channel: \(channelName.isEmpty ? "(unknown)" : channelName)
Sender: \(msg.sender)
Time: \(dateStr)

Message:
\(msg.content)

---
Reported via Parso IRC on \(Date().formatted(date: .abbreviated, time: .shortened))
"""

        let subject = "[Parso IRC] Content Report"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody    = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        let urlString = "mailto:info@parso.guru?subject=\(encodedSubject)&body=\(encodedBody)"

        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback: copy the report text to clipboard
            UIPasteboard.general.string = "To: info@parso.guru\nSubject: \(subject)\n\n\(body)"
            reportFallbackText = body
            showReportFallbackAlert = true
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
