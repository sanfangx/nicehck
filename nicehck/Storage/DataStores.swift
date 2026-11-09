import Foundation
import Combine

/// iOS 16.0 UserDefaults-backed replacement for SwiftData `@Model ConnectedDevice`
struct ConnectedDevice: Codable, Identifiable, Equatable, Hashable {
    var identify: String
    var deviceId: Int

    var id: String { identify }
}

final class ConnectedDeviceRepository: ObservableObject {
    static let shared = ConnectedDeviceRepository()

    private let storageKey = "nicehck_connected_devices_v1"
    @Published private(set) var devices: [ConnectedDevice] = []

    private init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ConnectedDevice].self, from: data) else {
            devices = []
            return
        }
        devices = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func saveDevice(identify: String, deviceId: Int) {
        if let idx = devices.firstIndex(where: { $0.identify.caseInsensitiveCompare(identify) == .orderedSame }) {
            if devices[idx].deviceId != deviceId {
                devices[idx].deviceId = deviceId
                persist()
            }
        } else {
            devices.append(ConnectedDevice(identify: identify, deviceId: deviceId))
            persist()
        }
    }

    func removeDevice(identify: String) {
        devices.removeAll { $0.identify.caseInsensitiveCompare(identify) == .orderedSame }
        persist()
    }

    func contains(identify: String) -> Bool {
        devices.contains { $0.identify.caseInsensitiveCompare(identify) == .orderedSame }
    }
}

/// Exact implementation of `ExperimentNoiseCancelingDataStore` (`0x100022b28`)
final class ExperimentNoiseCancelingDataStore: ObservableObject {
    static let shared = ExperimentNoiseCancelingDataStore()

    private let key = "experiment_noise_canceling_enabled_devices"
    @Published private(set) var enabledDeviceIds: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let set = try? JSONDecoder().decode(Set<String>.self, from: data) {
            enabledDeviceIds = set
        } else if let array = UserDefaults.standard.stringArray(forKey: key) {
            enabledDeviceIds = Set(array)
        }
    }

    func isEnabled(for deviceIdentify: String) -> Bool {
        enabledDeviceIds.contains(deviceIdentify)
    }

    func setEnabled(_ enabled: Bool, for deviceIdentify: String) {
        if enabled {
            enabledDeviceIds.insert(deviceIdentify)
        } else {
            enabledDeviceIds.remove(deviceIdentify)
        }
        if let data = try? JSONEncoder().encode(enabledDeviceIds) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Exact implementation of `LastNoiseCancelingDataStore` (`0x100023378`)
final class LastNoiseCancelingDataStore {
    static let shared = LastNoiseCancelingDataStore()

    private let key = "last_noise_canceling"

    private init() {}

    private func loadMap() -> [String: String] {
        if let data = UserDefaults.standard.data(forKey: key),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict
        }
        if let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            return dict
        }
        return [:]
    }

    private func saveMap(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func getLastMode(for deviceIdentify: String) -> NoiseMode {
        let map = loadMap()
        guard let raw = map[deviceIdentify],
              let mode = NoiseMode(rawValue: raw),
              mode.isNoiseCancelingSubMode else {
            return .on
        }
        return mode
    }

    func saveLastMode(_ mode: NoiseMode, for deviceIdentify: String) {
        guard mode.isNoiseCancelingSubMode else { return }
        var map = loadMap()
        map[deviceIdentify] = mode.rawValue
        saveMap(map)
    }
}

/// Exact implementation of `SetNoiseControlLogic` (`0x10008aae8 .. 0x10008b498`)
enum SetNoiseControlLogic {
    static func resolveTargetMode(
        for mainState: MainNoiseControlState,
        deviceIdentify: String
    ) -> NoiseMode {
        switch mainState {
        case .off:
            return .off
        case .transparency:
            return .transparency
        case .windNoiseCanceling:
            return .windNoiseCanceling
        case .noiseCanceling:
            let lastSubMode = LastNoiseCancelingDataStore.shared.getLastMode(for: deviceIdentify)
            if lastSubMode == .experimental_noise_canceling &&
               !ExperimentNoiseCancelingDataStore.shared.isEnabled(for: deviceIdentify) {
                return .on
            }
            return lastSubMode
        }
    }
}
