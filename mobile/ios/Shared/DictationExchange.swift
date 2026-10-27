import Foundation

// Only dictation text and control messages cross the App Group boundary. Keys stay in the app.
enum DictationExchange {
    static let group = "group.network.utterleaf.personal.mobile"
    static var directory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static func read(_ name: String) -> [String: Any] {
        guard let url = directory?.appendingPathComponent(name + ".json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
    static func write(_ value: [String: Any], to name: String) throws {
        guard let url = directory?.appendingPathComponent(name + ".json") else {
            throw NSError(domain: "UtterLeaf", code: 1, userInfo: [NSLocalizedDescriptionKey: "共享空间不可用，请检查 App Group 签名。"])
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }
    static func exportNavigationDiagnostics() {
        // Whitelist navigation-only state; never export dictation, target context, tickets or credentials.
        guard let source = directory,
              let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let destination = cache.appendingPathComponent("NavigationDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["keyboard-navigation", "app-navigation", "navigation-smoke"] {
            guard let data = try? Data(contentsOf: source.appendingPathComponent(name + ".json")), data.count < 16384 else { continue }
            try? data.write(to: destination.appendingPathComponent(name + ".json"), options: .atomic)
        }
    }
}
