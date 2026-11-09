import Foundation
import Combine

enum BluetoothConnectionState: String, Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting

    var localizedKey: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        }
    }
}

final class BatteryLevel: ObservableObject, Equatable {
    @Published var left: Int
    @Published var right: Int
    @Published var box: Int

    init(left: Int, right: Int, box: Int) {
        self.left = left
        self.right = right
        self.box = box
    }

    static func == (lhs: BatteryLevel, rhs: BatteryLevel) -> Bool {
        lhs.left == rhs.left && lhs.right == rhs.right && lhs.box == rhs.box
    }
}

enum NoiseMode: String, CaseIterable, Codable, Equatable {
    case off
    case transparency
    case on
    case deepNoiseCanceling
    case experimental_noise_canceling
    case windNoiseCanceling

    /// Exact wire byte table at 0x100008844 & 0x100049290 (`0x0000111003020100`)
    var wireByte: UInt8 {
        switch self {
        case .off: return 0x00
        case .transparency: return 0x01
        case .on: return 0x02
        case .deepNoiseCanceling: return 0x03
        case .experimental_noise_canceling: return 0x10
        case .windNoiseCanceling: return 0x11
        }
    }

    static func fromWireByte(_ byte: UInt8) -> NoiseMode? {
        switch byte {
        case 0x00: return .off
        case 0x01: return .transparency
        case 0x02: return .on
        case 0x03: return .deepNoiseCanceling
        case 0x10: return .experimental_noise_canceling
        case 0x11: return .windNoiseCanceling
        default: return nil
        }
    }

    var mainState: MainNoiseControlState {
        switch self {
        case .off:
            return .off
        case .transparency:
            return .transparency
        case .windNoiseCanceling:
            return .windNoiseCanceling
        case .on, .deepNoiseCanceling, .experimental_noise_canceling:
            return .noiseCanceling
        }
    }

    var isNoiseCancelingSubMode: Bool {
        switch self {
        case .on, .deepNoiseCanceling, .experimental_noise_canceling:
            return true
        default:
            return false
        }
    }

    var localizedKey: String {
        switch self {
        case .off: return "off"
        case .transparency: return "transparency"
        case .on: return "noise_canceling"
        case .deepNoiseCanceling: return "deep_noise_canceling"
        case .experimental_noise_canceling: return "experimental_noise_canceling"
        case .windNoiseCanceling: return "wind_noise"
        }
    }
}

enum MainNoiseControlState: String, CaseIterable, Equatable {
    case off
    case transparency
    case windNoiseCanceling
    case noiseCanceling

    var localizedKey: String {
        switch self {
        case .off: return "off"
        case .transparency: return "transparency"
        case .windNoiseCanceling: return "wind_noise"
        case .noiseCanceling: return "noise_canceling"
        }
    }

    var systemIconName: String {
        switch self {
        case .off: return "speaker.slash.fill"
        case .transparency: return "ear.and.waveform"
        case .windNoiseCanceling: return "wind"
        case .noiseCanceling: return "person.wave.2.fill"
        }
    }
}

enum NoiseFunc: UInt8, CaseIterable, Identifiable, Equatable {
    case off = 0x00
    case transparency = 0x01
    case on = 0x02

    var id: UInt8 { rawValue }
    var wireByte: UInt8 { rawValue }

    var localizedKey: String {
        switch self {
        case .off: return "off"
        case .transparency: return "transparency"
        case .on: return "noise_canceling"
        }
    }
}

final class NoiseControl: ObservableObject, Equatable {
    @Published var mode: NoiseMode

    init(mode: NoiseMode) {
        self.mode = mode
    }

    static func == (lhs: NoiseControl, rhs: NoiseControl) -> Bool {
        lhs.mode == rhs.mode
    }
}

final class AncTouchControlItem: ObservableObject, Identifiable, Equatable {
    let function: NoiseFunc
    @Published var isCheck: Bool

    var id: UInt8 { function.rawValue }

    init(function: NoiseFunc, isCheck: Bool) {
        self.function = function
        self.isCheck = isCheck
    }

    static func == (lhs: AncTouchControlItem, rhs: AncTouchControlItem) -> Bool {
        lhs.function == rhs.function && lhs.isCheck == rhs.isCheck
    }
}

final class AncTouchControl: ObservableObject, Equatable {
    @Published var ancTouchControlItems: [AncTouchControlItem]

    init(ancTouchControlItems: [AncTouchControlItem]) {
        self.ancTouchControlItems = ancTouchControlItems
    }

    static func == (lhs: AncTouchControl, rhs: AncTouchControl) -> Bool {
        lhs.ancTouchControlItems == rhs.ancTouchControlItems
    }
}

enum TouchControlSide: UInt8, CaseIterable, Identifiable, Equatable {
    case left = 0x01
    case right = 0x02

    var id: UInt8 { rawValue }
    var wireByte: UInt8 { rawValue }

    var localizedKey: String {
        switch self {
        case .left: return "left_control"
        case .right: return "right_control"
        }
    }
}

enum TouchControlKeyType: UInt8, Equatable {
    case noType = 0x01
    var wireByte: UInt8 { rawValue }
}

enum TouchControlOperation: UInt8, CaseIterable, Identifiable, Equatable {
    case oneClick = 0x01
    case doubleClick = 0x02
    case tripleClick = 0x03
    case longPress = 0x05

    var id: UInt8 { rawValue }
    var wireByte: UInt8 { rawValue }

    var localizedKey: String {
        switch self {
        case .oneClick: return "single_tap"
        case .doubleClick: return "double_tap"
        case .tripleClick: return "triple_tap"
        case .longPress: return "long_press"
        }
    }
}

enum TouchControlFunc: UInt8, CaseIterable, Identifiable, Equatable {
    case none = 0x00
    case playAndPause = 0x01
    case previousTrack = 0x02
    case nextTrack = 0x03
    case noiseCancelingSwitch = 0x04
    case volumeDown = 0x05
    case volumeUp = 0x06
    case gameMode = 0x07
    case voiceAssistant = 0x08

    var id: UInt8 { rawValue }
    var wireByte: UInt8 { rawValue }

    var localizedKey: String {
        switch self {
        case .none: return "touch_func_none"
        case .playAndPause: return "touch_func_play_and_pause"
        case .previousTrack: return "touch_func_previous_track"
        case .nextTrack: return "touch_func_next_track"
        case .noiseCancelingSwitch: return "touch_func_noise_control_switch"
        case .volumeDown: return "touch_func_volume_down"
        case .volumeUp: return "touch_func_volume_up"
        case .gameMode: return "touch_func_game_mode"
        case .voiceAssistant: return "touch_func_voice_assistant"
        }
    }
}

final class TouchControlItem: ObservableObject, Identifiable, Equatable {
    let side: TouchControlSide
    let keyType: TouchControlKeyType
    let operation: TouchControlOperation
    @Published var function: TouchControlFunc

    var id: String { "\(side.rawValue)-\(operation.rawValue)" }

    init(
        side: TouchControlSide,
        keyType: TouchControlKeyType = .noType,
        operation: TouchControlOperation,
        function: TouchControlFunc
    ) {
        self.side = side
        self.keyType = keyType
        self.operation = operation
        self.function = function
    }

    static func == (lhs: TouchControlItem, rhs: TouchControlItem) -> Bool {
        lhs.side == rhs.side &&
        lhs.keyType == rhs.keyType &&
        lhs.operation == rhs.operation &&
        lhs.function == rhs.function
    }
}

final class TouchControl: ObservableObject, Equatable {
    @Published var items: [TouchControlItem]

    init(items: [TouchControlItem]) {
        self.items = items
    }

    func items(for side: TouchControlSide) -> [TouchControlItem] {
        let filtered = items.filter { $0.side == side }
        return TouchControlOperation.allCases.compactMap { op in
            filtered.first(where: { $0.operation == op })
        }
    }

    static func == (lhs: TouchControl, rhs: TouchControl) -> Bool {
        lhs.items == rhs.items
    }
}

enum CodecEnum: UInt8, CaseIterable, Identifiable, Equatable {
    case acc = 0x00
    case lhdc = 0x01

    var id: UInt8 { rawValue }

    var displayName: String {
        switch self {
        case .acc: return "AAC"
        case .lhdc: return "LHDC"
        }
    }
}

final class BtDeviceInfo: ObservableObject {
    @Published var btDeviceId: String?
    @Published var firmwareVersion: String?
    @Published var serialNumber: String?
    @Published var batteryLevel: BatteryLevel?
    @Published var noiseControl: NoiseControl?
    @Published var ancTouchControl: AncTouchControl?
    @Published var toneVolume: Int?
    @Published var touchControl: TouchControl?
    @Published var codec: CodecEnum?
    @Published var dualConnection: Bool?
    @Published var lowLatencyMode: Bool?
    @Published var eqIndex: Int?
    @Published var gameMode: Bool?
    @Published var inEarDetection: Bool?
    @Published var experimentWind: Bool?

    var firmwareVersionInt: Int {
        guard let fw = firmwareVersion else { return 0 }
        let digitsOnly = fw.replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(digitsOnly) ?? 0
    }
}
