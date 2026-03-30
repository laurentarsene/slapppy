import SwiftUI

struct ActivationView: View {
    @Environment(LicenseManager.self) private var license
    @State private var keyInput = ""

    var body: some View {
        VStack(spacing: 20) {

            // ── Header ────────────────────────────────────────────────
            VStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.accent)
                Text("Activate Slapppy")
                    .font(.headline)
                Text("Enter your license key from the\npurchase confirmation email.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            // ── Input ─────────────────────────────────────────────────
            VStack(spacing: 8) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(license.isValidating)
                    .onSubmit { Task { await activate() } }

                if let err = license.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await activate() }
                } label: {
                    if license.isValidating {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Activate")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmed.isEmpty || license.isValidating)
                .keyboardShortcut(.defaultAction)
            }

            // ── Footer ────────────────────────────────────────────────
            Link("Don't have a license? Get Slapppy →",
                 destination: URL(string: "https://slapppy.com/#download")!)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 300)
    }

    private var trimmed: String {
        keyInput.trimmingCharacters(in: .whitespaces)
    }

    private func activate() async {
        await license.activate(key: trimmed)
    }
}
