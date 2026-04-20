import SwiftUI

/// Appearance settings — font size and message density.
///
/// All values are stored in `UserDefaults` via `@AppStorage` so they're
/// instantly available across the app without extra infrastructure.
struct AppearanceSettingsView: View {

    @AppStorage("messageFontSize") private var messageFontSize: Double = 15
    @AppStorage("messageDensity") private var messageDensity: String = "comfortable"

    private let densityOptions: [(label: String, value: String, icon: String)] = [
        ("Comfortable", "comfortable", "text.alignleft"),
        ("Compact",     "compact",     "text.justify"),
    ]

    var body: some View {
        Form {
            // Font size
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(messageFontSize))pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $messageFontSize, in: 11...21, step: 1)
                            .tint(.accentColor)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }
                    // Live preview
                    Text("The quick brown fox jumps over the lazy dog")
                        .font(.system(size: messageFontSize))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Font Size")
            }

            // Density
            Section {
                ForEach(densityOptions, id: \.value) { option in
                    HStack {
                        Label(option.label, systemImage: option.icon)
                        Spacer()
                        if messageDensity == option.value {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { messageDensity = option.value }
                }
            } header: {
                Text("Message Density")
            } footer: {
                Text("Comfortable adds more space between message groups for easier reading.")
                    .font(.caption)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AppStorage keys (shared constants)

extension AppStorage where Value == Double {
    static let messageFontSizeKey = "messageFontSize"
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
