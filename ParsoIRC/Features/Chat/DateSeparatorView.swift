import SwiftUI

/// A centered date-pill separator between groups of messages.
///
/// Shows "Today", "Yesterday", or a formatted date like "April 17, 2026".
struct DateSeparatorView: View {
    let date: Date

    private var label: String { date.formattedDate() }

    var body: some View {
        HStack(spacing: 8) {
            line
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            line
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }

    private var line: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(height: 0.5)
    }
}

#Preview {
    VStack(spacing: 0) {
        DateSeparatorView(date: Date())
        DateSeparatorView(date: Date().addingTimeInterval(-86400))
        DateSeparatorView(date: Date().addingTimeInterval(-86400 * 5))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
