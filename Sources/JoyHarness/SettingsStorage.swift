import Foundation

enum SettingsStorage {
    static func contains(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: "JoyHarness." + key) != nil
    }

    static func load<T: Decodable>(_ type: T.Type, _ key: String, defaults: UserDefaults = .standard) -> T? {
        guard let data = defaults.data(forKey: "JoyHarness." + key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Initialization may immediately save defaults over this key.
            // Retain the unreadable data separately for manual recovery.
            defaults.set(data, forKey: "JoyHarness.recovery." + key)
            Log.settings.error("Settings could not be decoded; recovery copy saved for \(key, privacy: .public)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, _ key: String, defaults: UserDefaults = .standard) {
        do {
            try write(value, key, defaults: defaults)
        } catch {
            Log.settings.error("Settings could not be encoded for \(key, privacy: .public); previous value retained")
        }
    }

    static func write<T: Encodable>(_ value: T, _ key: String, defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: "JoyHarness." + key)
    }
}
