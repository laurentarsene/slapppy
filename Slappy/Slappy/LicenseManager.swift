import Foundation
import Security

// ── Polar config ───────────────────────────────────────────────────────
// Find your Organization ID: polar.sh/dashboard → Settings → General
private let kPolarOrgID = "YOUR_POLAR_ORGANIZATION_ID"
// ──────────────────────────────────────────────────────────────────────

@Observable
final class LicenseManager {

    var isActivated:  Bool    = false
    var isValidating: Bool    = false
    var errorMessage: String?

    private let service          = "com.slapppy.app"
    private let keyAccount       = "license-key"
    private let machineIDAccount = "machine-id"

    init() {
        // Already activated if both artefacts are in Keychain
        isActivated = keychainRead(keyAccount) != nil
                   && keychainRead(machineIDAccount) != nil
    }

    // MARK: – Public

    func activate(key: String) async {
        await MainActor.run { isValidating = true; errorMessage = nil }

        let body: [String: Any] = [
            "key":             key,
            "organization_id": kPolarOrgID,
            "label":           "mac-\(machineID().prefix(8))"
        ]

        guard let url  = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/activate"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            await setError("Configuration error.")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                keychainWrite(keyAccount, value: key)
                await MainActor.run { isActivated = true; isValidating = false }
            } else {
                let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any]
                let msg: String
                if let detail = json?["detail"] as? String {
                    msg = detail
                } else if status == 404 {
                    msg = "License key not found."
                } else if status == 409 || status == 422 {
                    msg = "This key has reached its activation limit."
                } else {
                    msg = "Activation failed (error \(status))."
                }
                await setError(msg)
            }
        } catch {
            await setError("Network error. Check your connection.")
        }
    }

    // MARK: – Private

    /// Stable machine ID — generated once and stored in Keychain.
    private func machineID() -> String {
        if let id = keychainRead(machineIDAccount) { return id }
        let id = UUID().uuidString
        keychainWrite(machineIDAccount, value: id)
        return id
    }

    private func setError(_ msg: String) async {
        await MainActor.run { errorMessage = msg; isValidating = false }
    }

    private func keychainWrite(_ account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    private func keychainRead(_ account: String) -> String? {
        var result: AnyObject?
        let q: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
