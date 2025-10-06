import SwiftUI

struct SettingsView: View {
    @State private var maxLanes: Int = AppConfig.shared.maxLanes
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Race Configuration")
                        .font(.headline)

                    HStack {
                        Text("Maximum Number of Lanes:")
                        Spacer()
                        TextField("Lanes", value: $maxLanes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onChange(of: maxLanes) { newValue in
                                // Validate range
                                if newValue < 1 {
                                    maxLanes = 1
                                } else if newValue > 12 {
                                    maxLanes = 12
                                }
                            }
                    }

                    Text("Valid range: 1-12 lanes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Note: Changing the number of lanes will take effect when you create a new race.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    AppConfig.shared.maxLanes = maxLanes
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

#Preview {
    SettingsView()
}