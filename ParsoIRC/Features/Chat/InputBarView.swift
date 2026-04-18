import SwiftUI

/// The bottom input bar: text field, send button, and a `+` action menu.
///
/// When the user types `/` as the first character a compact command suggestion
/// strip appears above the keyboard listing matching slash commands.
struct InputBarView: View {
    @ObservedObject var viewModel: ChannelViewModel

    // Pre-fill text from outside (e.g. "alice: " after tapping a nick)
    @Binding var prefillText: String

    @State private var inputText: String = ""
    @FocusState private var isTextFieldFocused: Bool

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

    private var showAutocomplete: Bool { !filteredCommands.isEmpty && inputText != filteredCommands.first?.cmd }
    private var canSend: Bool { !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Slash-command autocomplete strip
            if showAutocomplete {
                commandSuggestions
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

                // Text field
                TextField("Message \(viewModel.channelName)", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isTextFieldFocused)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
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
                        .animation(.easeInOut(duration: 0.15), value: canSend)
                }
                .disabled(!canSend)
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
    }

    /// Submit on Return key only when the text is a single line (no \n).
    private func submitIfSingleLine() {
        if !inputText.contains("\n") { send() }
    }
}
