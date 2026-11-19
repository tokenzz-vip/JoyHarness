import Foundation

struct ConfigurationImportPreview: Identifiable {
    let id = UUID()
    let source: String
    let isRecovery: Bool
    let configuration: Configuration
    var editingProfileID: UUID?

    private static let limit = 2_000_000

    static func encodeBackup(_ configuration: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(configuration.validated())
        guard data.count <= limit else { throw ImportError.fileTooLarge }
        return data
    }

    static func read(from url: URL) throws -> ConfigurationImportPreview {
        let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resource.isRegularFile == true else { throw ImportError.invalidFile }
        guard (resource.fileSize ?? 0) <= limit else { throw ImportError.fileTooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ImportError.fileTooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["profiles"] is [Any],
              let decoded = try? JSONDecoder().decode(Configuration.self, from: data) else {
            throw ImportError.invalidFile
        }
        let configuration = try decoded.validated()
            .addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses().addingBuiltInPhrases().validated()
        return .init(source: url.lastPathComponent, isRecovery: false, configuration: configuration)
    }

    enum ImportError: LocalizedError {
        case invalidFile, fileTooLarge, stalePreview

        var errorDescription: String? {
            switch self {
            case .invalidFile: "请选择 JoyHarness 导出的 JSON 配置文件。"
            case .fileTooLarge: "配置文件大小不能超过 2 MB。"
            case .stalePreview: "此预览已失效，请重新选择配置。"
            }
        }
    }
}

struct ConfigurationRecovery: Codable {
    let date: Date
    let configuration: Configuration
    let editingProfileID: UUID
}

/// Stores the new configuration and its recovery point in one preferences value.
/// Legacy configurations use the same top-level keys without a recovery point.
struct StoredConfiguration: Codable {
    let configuration: Configuration
    let recovery: ConfigurationRecovery?

    private enum CodingKeys: String, CodingKey {
        case replacementRecovery
    }

    init(configuration: Configuration, recovery: ConfigurationRecovery?) {
        self.configuration = configuration
        self.recovery = recovery
    }

    init(from decoder: Decoder) throws {
        configuration = try Configuration(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        recovery = try? values.decode(ConfigurationRecovery.self, forKey: .replacementRecovery)
    }

    func encode(to encoder: Encoder) throws {
        try configuration.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(recovery, forKey: .replacementRecovery)
    }
}
