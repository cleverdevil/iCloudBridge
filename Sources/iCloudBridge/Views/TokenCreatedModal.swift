import SwiftUI

struct TokenCreatedModal: View {
    let token: String
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Token Created")
                .font(.headline)

            Text("Copy this token now. It will only be shown once.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            GroupBox {
                HStack {
                    Text(token)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()

                    Button(action: copyToken) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity)

            if copied {
                Text("Copied to clipboard!")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 400)
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        copied = true
    }
}
