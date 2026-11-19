import AppKit

/// Keep the built-in applications and identifiers aligned with RcHarness.
struct HarnessApplication: Equatable, Identifiable {
    let id: String
    let name: String
    let bundleIdentifiers: [String]

    // The installed ChatGPT app retains this Bundle ID.
    static let chatGPT = Self(id: "chatgpt", name: "ChatGPT", bundleIdentifiers: ["com.openai.codex"])
    var defaultApplicationPath: String { "/Applications/\(name).app" }

    static let defaults: [Self] = [
        chatGPT,
        .init(id: "claude", name: "Claude", bundleIdentifiers: ["com.anthropic.claudefordesktop"]),
        .init(id: "cursor", name: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]),
        .init(id: "deepseek", name: "DeepSeek", bundleIdentifiers: ["com.deepseek.dsh"]),
        .init(id: "workbuddy", name: "WorkBuddy", bundleIdentifiers: ["com.tencent.workbuddy.mac", "com.workbuddy.workbuddy"]),
        .init(id: "opencode", name: "OpenCode", bundleIdentifiers: ["ai.opencode.desktop"]),
    ]

    func matches(bundleID: String) -> Bool {
        bundleIdentifiers.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    static func matching(bundleID: String) -> Self? {
        defaults.first { $0.matches(bundleID: bundleID) }
    }
}

extension HarnessBinding {
    var builtIn: HarnessApplication? { HarnessApplication.matching(bundleID: bundleID) }
    var isBuiltIn: Bool { builtIn != nil }
    var applicationIdentifiers: [String] { builtIn?.bundleIdentifiers ?? [bundleID] }
    var canonicalBundleID: String { (builtIn?.bundleIdentifiers.first ?? bundleID).lowercased() }

    func matches(bundleID identifier: String?) -> Bool {
        guard let identifier else { return false }
        return applicationIdentifiers.contains { $0.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    func matches(applicationPath path: String?, bundleIdentifier identifier: String?) -> Bool {
        if let identifier { return matches(bundleID: identifier) }
        guard let path else { return false }
        return URL(fileURLWithPath: applicationPath).standardizedFileURL == URL(fileURLWithPath: path).standardizedFileURL
    }

    var installedApplicationURL: URL? {
        installedApplicationURL(resolve: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
    }

    func installedApplicationURL(resolve: (String) -> URL?) -> URL? {
        for identifier in applicationIdentifiers {
            if let url = resolve(identifier) { return url }
        }
        guard FileManager.default.fileExists(atPath: applicationPath) else { return nil }
        return URL(fileURLWithPath: applicationPath)
    }
}

extension Configuration {
    /// Upgrade saved settings and imports without replacing user bindings or mappings.
    func addingBuiltInHarnesses() -> Self {
        var result = self
        guard let profileID = defaultProfileID ?? profiles.first?.id else { return result }
        let chatGPT = HarnessApplication.chatGPT
        if let index = result.harnesses.firstIndex(where: { $0.builtIn == chatGPT }) {
            result.harnesses[index].applicationPath = chatGPT.defaultApplicationPath
        }
        for application in HarnessApplication.defaults where !result.harnesses.contains(where: {
            application.matches(bundleID: $0.bundleID)
        }) {
            let presetID = DefaultKeyProfiles.id(for: application)
            result.harnesses.append(.init(applicationPath: application.defaultApplicationPath,
                                          bundleID: application.bundleIdentifiers[0],
                                          profileID: profiles.contains(where: { $0.id == presetID }) ? presetID : profileID))
        }
        return result
    }
}
