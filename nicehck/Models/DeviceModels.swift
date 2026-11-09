import Foundation
import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .system: return "theme_system"
        case .light: return "theme_light"
        case .dark: return "theme_dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct Device: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let customName: String?
    let tag: String?
    let model: String?
    let imageUrl: String?
    let previewImageUrl: String?

    var displayName: String {
        if let customName = customName, !customName.isEmpty {
            return customName
        }
        return name
    }

    var detailAssetName: String {
        imageUrl ?? "OriginDetail"
    }

    var previewAssetName: String {
        previewImageUrl ?? "OriginPreview"
    }
}

enum FeatureType: String, Codable, CaseIterable {
    case BtNoiseControl
    case BtEqualizerSetting
    case BtToneVolume
    case BtGameMode
    case BtLatencyMode
    case BtDualConnection
    case BtCodecControl
    case BtTouchControl
    case BtInEarDetection
    case BtOTA
    case BtOriginExperiment
    case BtFindEarbuds
    case BtGameModeV2
    case BtLatencyModeV2
    case BtTouchControlWithAncControl
}

struct Feature: Codable, Identifiable, Equatable {
    let id: Int
    let deviceId: Int
    let featureOptionId: Int
    let type: String
    let priority: Int
    let minVersion: Int
    let maxVersion: Int
    let section: String?

    var featureType: FeatureType? {
        FeatureType(rawValue: type)
    }
}

struct FeatureOption: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let priority: Int
}

struct BtEqualizer: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let deviceId: Int
    let eqIndex: Int
    let priority: Int
    let minVersion: Int
    let maxVersion: Int
}

struct FeatureGroup: Identifiable {
    let option: FeatureOption
    let features: [Feature]

    var id: Int { option.id }
}

final class DeviceManager {
    static let shared = DeviceManager()

    private(set) var devices: [Device] = []
    private(set) var features: [Feature] = []
    private(set) var featureOptions: [FeatureOption] = []
    private(set) var equalizers: [BtEqualizer] = []

    private init() {
        loadAllConfigs()
    }

    private func loadAllConfigs() {
        devices = loadJSON("devices", fallback: [
            Device(
                id: 2,
                name: "YUANDAO OriG in",
                customName: "OriG in",
                tag: "YUANDAO Wireless Device",
                model: "ACC SPP V1",
                imageUrl: "OriginDetail",
                previewImageUrl: "originPreview"
            )
        ])
        featureOptions = loadJSON("featureOptions", fallback: [])
            .sorted { $0.priority < $1.priority }
        features = loadJSON("features", fallback: [])
            .sorted { $0.priority < $1.priority }
        equalizers = loadJSON("btEqualizerConfig", fallback: [])
            .sorted { $0.priority < $1.priority }
    }

    private func loadJSON<T: Decodable>(_ resourceName: String, fallback: T) -> T {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let rawText = try? String(contentsOf: url, encoding: .utf8) else {
            return fallback
        }
        // Clean any accidental trailing comma before decoding
        let cleaned = rawText.replacingOccurrences(
            of: ",\\s*([}\\]])",
            with: "$1",
            options: .regularExpression
        )
        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return fallback
        }
        return decoded
    }

    func device(forId id: Int) -> Device? {
        devices.first(where: { $0.id == id }) ?? devices.first
    }

    func matchSupportedDevice(peripheralName: String) -> Device? {
        let trimmed = peripheralName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for dev in devices {
            if trimmed == dev.name {
                return dev
            }
            if let custom = dev.customName, !custom.isEmpty, trimmed == custom {
                return dev
            }
            if trimmed.localizedCaseInsensitiveContains("YUANDAO") ||
               trimmed.localizedCaseInsensitiveContains("OriG in") ||
               trimmed.localizedCaseInsensitiveContains("Origin") {
                return dev
            }
        }
        return nil
    }

    func featureGroups(for deviceId: Int, firmwareVersion: Int) -> [FeatureGroup] {
        let validFeatures = features.filter { feat in
            feat.deviceId == deviceId &&
            feat.minVersion <= firmwareVersion &&
            firmwareVersion <= feat.maxVersion
        }
        return featureOptions.compactMap { option in
            let matching = validFeatures
                .filter { $0.featureOptionId == option.id }
                .sorted { $0.priority < $1.priority }
            guard !matching.isEmpty else { return nil }
            return FeatureGroup(option: option, features: matching)
        }
    }

    func availableEqualizers(for deviceId: Int, firmwareVersion: Int) -> [BtEqualizer] {
        equalizers
            .filter { eq in
                eq.deviceId == deviceId &&
                eq.minVersion <= firmwareVersion &&
                firmwareVersion <= eq.maxVersion
            }
            .sorted { $0.priority < $1.priority }
    }
}
