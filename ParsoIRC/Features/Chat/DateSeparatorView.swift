import SwiftUI

struct DateSeparatorView: View {
    let date: Date
    
    var body: some View {
        HStack {
            Spacer()
            Text(date.formattedDate())
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack {
        DateSeparatorView(date: Date())
        DateSeparatorView(date: Date().addingTimeInterval(-86400))
        DateSeparatorView(date: Date().addingTimeInterval(-172800))
    }
}