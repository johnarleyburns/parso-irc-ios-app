import SwiftUI

/// The bottom input bar: text field, send button, and a `+` action menu.
///
/// Features:
/// - Slash-command autocomplete strip when the user types `/`
/// - Nick completion strip when the user types `@` or starts a word that matches members
/// - Keyboard submit on Return (single-line messages only)
struct InputBarView: View {
    @ObservedObject var viewModel: ChannelViewModel

    // Pre-fill text from outside (e.g. "alice: " after tapping a nick)
    @Binding var prefillText: String

    /// Optional callback invoked after a message is sent (used by demo mode step tracking).
    var onSend: (() -> Void)? = nil

    @State private var inputText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Slash-command autocomplete
    private let slashCommands: [(cmd: String, hint: String)] = [
        ("/me",     "Send an action"),
        ("/nick",   "Change your nickname"),
        ("/join",   "Join a channel"),
        ("/part",   "Leave this channel"),
        ("/topic",  "Set or view topic"),
        ("/kick",   "Kick a user"),
        ("/mode",   "Set channel mode"),
        ("/whois",  "Query a user"),
        ("/msg",    "Send a private message"),
        ("/away",   "Set away message"),
        ("/quit",   "Disconnect from server"),
        ("/names",  "List users in channel"),
        ("/list",   "List channels"),
        ("/who",    "WHO query"),
    ]

    private var filteredCommands: [(cmd: String, hint: String)] {
        guard inputText.hasPrefix("/") else { return [] }
        let lower = inputText.lowercased()
        return slashCommands.filter { $0.cmd.hasPrefix(lower) }
    }

    // Nick completion: active when last word starts with @ or just letters
    private var nickCompletionPrefix: String? {
        guard !inputText.hasPrefix("/") else { return nil }
        let words = inputText.split(separator: " ", omittingEmptySubsequences: false)
        let last = String(words.last ?? "")
        guard !last.isEmpty else { return nil }
        let stripped = last.hasPrefix("@") ? String(last.dropFirst()) : last
        guard !stripped.isEmpty else { return nil }
        return stripped.lowercased()
    }

    private var nickSuggestions: [String] {
        guard let prefix = nickCompletionPrefix else { return [] }
        return viewModel.members
            .filter { $0.nick.lowercased().hasPrefix(prefix) }
            .map(\.nick)
            .sorted()
    }

    private var showSlashAutocomplete: Bool { !filteredCommands.isEmpty && inputText != filteredCommands.first?.cmd }
    private var showNickCompletion: Bool { !nickSuggestions.isEmpty && nickCompletionPrefix != nil && nickCompletionPrefix!.count >= 1 }
    private var canSend: Bool { !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Autocomplete strip (slash commands or nick completion)
            if showSlashAutocomplete {
                commandSuggestions
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else if showNickCompletion {
                nickSuggestionStrip
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                // + action menu
                Menu {
                    actionMenuContent
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Attachments and commands")

                // Text field
                TextField("Message \(viewModel.channelName)", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isTextFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .onSubmit { submitIfSingleLine() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )

                // Send button
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray3))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: canSend)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        // Pre-fill from external source (nick tap, mention)
        .onChange(of: prefillText) { _, newVal in
            guard !newVal.isEmpty else { return }
            inputText = newVal
            prefillText = ""
            isTextFieldFocused = true
        }
    }

    // MARK: - Nick completion strip

    private var nickSuggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(nickSuggestions, id: \.self) { nick in
                    Button {
                        completeNick(nick)
                    } label: {
                        HStack(spacing: 4) {
                            AvatarView(nick: nick, size: 18, showBorder: false)
                            Text(nick)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    private func completeNick(_ nick: String) {
        // Replace the last word with the completed nick + ": " (IRC convention for first word)
        // or just the nick + " " if it's mid-sentence
        var words = inputText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if words.isEmpty {
            inputText = nick + ": "
        } else {
            let isFirstWord = words.count == 1
            words[words.count - 1] = isFirstWord ? nick + ": " : nick + " "
            inputText = words.joined(separator: " ")
        }
        HapticManager.selectionFeedback()
    }

    // MARK: - Autocomplete strip

    private var commandSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filteredCommands, id: \.cmd) { entry in
                    Button {
                        inputText = entry.cmd + " "
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.cmd)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(entry.hint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Action menu

    @ViewBuilder
    private var actionMenuContent: some View {
        Button {
            inputText = "/me "
            isTextFieldFocused = true
        } label: {
            Label("Action (/me)", systemImage: "sparkles")
        }

        Button {
            inputText = "/join "
            isTextFieldFocused = true
        } label: {
            Label("Join Channel", systemImage: "number")
        }

        Button {
            inputText = "/msg "
            isTextFieldFocused = true
        } label: {
            Label("Private Message", systemImage: "envelope")
        }

        Button {
            inputText = "/whois "
            isTextFieldFocused = true
        } label: {
            Label("WHOIS", systemImage: "person.text.rectangle")
        }

        Divider()

        Button {
            inputText = "/topic "
            isTextFieldFocused = true
        } label: {
            Label("Set Topic", systemImage: "text.quote")
        }

        Button {
            inputText = "/names "
            isTextFieldFocused = true
        } label: {
            Label("List Members", systemImage: "person.2")
        }
    }

    // MARK: - Sending

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.send(trimmed)
        inputText = ""
        onSend?()
    }

    /// Submit on Return key only when the text is a single line (no \n).
    private func submitIfSingleLine() {
        if !inputText.contains("\n") { send() }
    }
}
