import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    var onSend: () -> Void
    var onCommand: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var textHeight: CGFloat = 44
    private let minHeight: CGFloat = 44
    private let maxHeight: CGFloat = 120
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                onCommand()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            ZStack(alignment: .bottomLeading) {
                if text.isEmpty {
                    Text("Message \(Text("#channel").foregroundColor(.secondary))")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                }
                
                TextField("", text: $text, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...5)
                    .frame(minHeight: minHeight, maxHeight: textHeight)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        updateHeight(for: newValue)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.theme.inputBarBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundColor(text.isEmpty ? .secondary : Color.theme.sentBubble)
            }
            .disabled(text.isEmpty)
        }
    }
    
    private func updateHeight(for text: String) {
        let lineHeight: CGFloat = 20
        let padding: CGFloat = 16
        let calculatedHeight = min(maxHeight, max(minHeight, ceil(lineHeight * CGFloat(text.components(separatedBy: "\n").count)) + padding))
        textHeight = calculatedHeight
    }
}

#Preview {
    @State var text = ""
    
    VStack {
        Spacer()
        InputBarView(text: $text, onSend: {}, onCommand: {})
            .padding()
            .background(Color.gray.opacity(0.1))
    }
}