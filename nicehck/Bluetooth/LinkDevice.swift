import Foundation
import CoreBluetooth
import Combine

final class LinkDevice: NSObject, ObservableObject, Identifiable {
    // MARK: - GATT UUID Constants (`0x10000bf30 .. 0x10000c0e0`)
    static let originServiceUUIDString = "0000A100-1000-8000-4E48-434B4354524C"
    static let writeCharacteristicUUIDString = "0000A100-1001-8000-4E48-434B4354524C"
    static let notifyCharacteristicUUIDString = "0000A100-1002-8000-4E48-434B4354524C"
    static let otaServiceUUIDString = "66666666-6666-6666-6666-666666666666"
    static let otaCharacteristicUUIDString = "77777777-7777-7777-7777-777777777777"

    static let originServiceUUID = CBUUID(string: originServiceUUIDString)
    static let writeCharacteristicUUID = CBUUID(string: writeCharacteristicUUIDString)
    static let notifyCharacteristicUUID = CBUUID(string: notifyCharacteristicUUIDString)
    static let otaServiceUUID = CBUUID(string: otaServiceUUIDString)
    static let otaCharacteristicUUID = CBUUID(string: otaCharacteristicUUIDString)

    // MARK: - Published Properties
    let identify: String
    let device: Device
    @Published var peripheral: CBPeripheral?
    @Published var connectionState: BluetoothConnectionState = .disconnected
    @Published var btDeviceInfo = BtDeviceInfo()
    @Published var isOTAReady: Bool = false

    var id: String { identify }

    // MARK: - Internal BLE State
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private(set) var otaCharacteristic: CBCharacteristic?
    private var receiveBuffer = Data()
    private var commandQueue: [Data] = []
    private var isProcessingQueue = false
    private var cancellables = Set<AnyCancellable>()

    /// Callback for OTA notification packets on `77777777-7777-7777-7777-777777777777`
    var onOTADataReceived: ((Data) -> Void)?

    init(identify: String, device: Device, peripheral: CBPeripheral? = nil) {
        self.identify = identify
        self.device = device
        self.peripheral = peripheral
        super.init()

        btDeviceInfo.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        if let p = peripheral {
            p.delegate = self
        }
    }

    func attachPeripheral(_ newPeripheral: CBPeripheral) {
        self.peripheral = newPeripheral
        newPeripheral.delegate = self
    }

    func handleConnected() {
        DispatchQueue.main.async {
            self.connectionState = .connected
        }
        receiveBuffer.removeAll()
        peripheral?.discoverServices(nil)
    }

    func handleDisconnected() {
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.isOTAReady = false
        }
        writeCharacteristic = nil
        notifyCharacteristic = nil
        otaCharacteristic = nil
        receiveBuffer.removeAll()
        commandQueue.removeAll()
    }

    // MARK: - Command Queue & Pacing (`100 ms` per command at `0x100046a50`)
    func enqueueCommand(_ data: Data) {
        DispatchQueue.main.async {
            self.commandQueue.append(data)
            self.processCommandQueueIfNeeded()
        }
    }

    private func processCommandQueueIfNeeded() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        Task { @MainActor [weak self] in
            while let self = self, !self.commandQueue.isEmpty {
                let nextData = self.commandQueue.removeFirst()
                self.writeControlData(nextData)
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            self?.isProcessingQueue = false
        }
    }

    /// Write to Control Characteristic (`0000A100-1001-...`, `0x100049bc0`)
    func writeControlData(_ data: Data) {
        guard let peripheral = peripheral,
              peripheral.state == .connected,
              let characteristic = writeCharacteristic else {
            return
        }
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    /// Write to OTA Characteristic (`77777777-...`, `0x100049d40`)
    func writeOTAData(_ data: Data) -> Bool {
        guard let peripheral = peripheral,
              peripheral.state == .connected,
              let characteristic = otaCharacteristic else {
            return false
        }
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        return true
    }

    // MARK: - 16-Command Initial State Query (`LinkDevice.queryAllState`, `0x10004a924`)
    func queryAllState() {
        let queryCommands: [UInt16] = [
            0x0001, // btDeviceId
            0x0002, // reserved/ignored
            0x0003, // firmwareVersion
            0x0004, // serialNumber
            0x0005, // batteryLevel
            0x0101, // noiseControl
            0x0102, // toneVolume
            0x0103, // touchControl
            0x0104, // codec
            0x0105, // dualConnection
            0x0106, // lowLatencyMode
            0x0107, // eqIndex
            0x0108, // gameMode
            0x0109, // inEarDetection
            0x01E1, // experimentWind
            0x010A  // ancTouchControl
        ]
        for cmd in queryCommands {
            enqueueCommand(GattCommandBuilder.build(command: cmd, payload: [], includeCrc: false))
        }
    }

    // MARK: - 11 Set / Action Commands (`0x100049210 .. 0x10004a3ac`)

    /// `0x0201` Set Noise Control (`0x100049210`)
    func setNoiseControl(mode: NoiseMode) {
        DispatchQueue.main.async {
            self.btDeviceInfo.noiseControl = NoiseControl(mode: mode)
        }
        if mode.isNoiseCancelingSubMode && mode != .experimental_noise_canceling {
            LastNoiseCancelingDataStore.shared.saveLastMode(mode, for: identify)
        }
        let cmd = GattCommandBuilder.build(command: 0x0201, payload: [mode.wireByte], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0101, payload: [], includeCrc: false))
    }

    /// `0x0202` Set Prompt Tone Volume (`0x100049958`)
    func setToneVolume(_ volume: Int) {
        let clamped = UInt8(max(0, min(100, volume)))
        DispatchQueue.main.async {
            self.btDeviceInfo.toneVolume = Int(clamped)
        }
        let cmd = GattCommandBuilder.build(command: 0x0202, payload: [clamped], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0101, payload: [], includeCrc: false))
        enqueueCommand(GattCommandBuilder.build(command: 0x0102, payload: [], includeCrc: false))
    }

    /// `0x0203` Set Touch Control (`0x100049f00`)
    func setTouchControl(side: TouchControlSide, operation: TouchControlOperation, function: TouchControlFunc) {
        let payload: [UInt8] = [
            side.wireByte,
            TouchControlKeyType.noType.wireByte,
            operation.wireByte,
            function.wireByte
        ]
        let cmd = GattCommandBuilder.build(command: 0x0203, payload: payload, includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0103, payload: [], includeCrc: false))
    }

    /// `0x0205` Set Dual Device Connection (`0x100049b78`)
    func setDualConnection(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.btDeviceInfo.dualConnection = enabled
        }
        let cmd = GattCommandBuilder.build(command: 0x0205, payload: [enabled ? 0x01 : 0x00], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0105, payload: [], includeCrc: false))
    }

    /// `0x0206` Set Low Latency Mode (`0x100049730`)
    func setLowLatencyMode(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.btDeviceInfo.lowLatencyMode = enabled
        }
        let cmd = GattCommandBuilder.build(command: 0x0206, payload: [enabled ? 0x01 : 0x00], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0106, payload: [], includeCrc: false))
    }

    /// `0x0207` Set Equalizer Preset Index (`0x100049d90`)
    func setEqIndex(_ eqIndex: Int) {
        let byte = UInt8(clamping: eqIndex)
        DispatchQueue.main.async {
            self.btDeviceInfo.eqIndex = eqIndex
        }
        let cmd = GattCommandBuilder.build(command: 0x0207, payload: [byte], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0107, payload: [], includeCrc: false))
    }

    /// `0x0208` Set Game Mode (`0x100049518`)
    func setGameMode(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.btDeviceInfo.gameMode = enabled
        }
        let cmd = GattCommandBuilder.build(command: 0x0208, payload: [enabled ? 0x01 : 0x00], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0108, payload: [], includeCrc: false))
    }

    /// `0x0209` Set In-Ear Detection (`0x10004a194`)
    func setInEarDetection(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.btDeviceInfo.inEarDetection = enabled
        }
        let cmd = GattCommandBuilder.build(command: 0x0209, payload: [enabled ? 0x01 : 0x00], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x0109, payload: [], includeCrc: false))
    }

    /// `0x020A` Set ANC Touch Loop Control (`0x10004a3ac`)
    func setAncTouchControl(items: [AncTouchControlItem]) {
        var payload: [UInt8] = []
        payload.reserveCapacity(items.count * 2)
        for item in items {
            payload.append(item.function.wireByte)
            payload.append(item.isCheck ? 0x01 : 0x00)
        }
        let cmd = GattCommandBuilder.build(command: 0x020A, payload: payload, includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x010A, payload: [], includeCrc: false))
    }

    /// `0x02E1` Set Experimental Wind Noise Mode (`0x1000649f0`)
    func setExperimentWind(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.btDeviceInfo.experimentWind = enabled
        }
        let cmd = GattCommandBuilder.build(command: 0x02E1, payload: [enabled ? 0x01 : 0x00], includeCrc: false)
        enqueueCommand(cmd)
        enqueueCommand(GattCommandBuilder.build(command: 0x01E1, payload: [], includeCrc: false))
        if !enabled && btDeviceInfo.noiseControl?.mode == .windNoiseCanceling {
            setNoiseControl(mode: .on)
        }
    }

    /// Toggle Experimental Deep Noise Canceling (`ExperimentFeatureView`, `0x1000649f0`)
    func setExperimentalNoiseCanceling(_ enabled: Bool) {
        ExperimentNoiseCancelingDataStore.shared.setEnabled(enabled, for: identify)
        if enabled {
            setNoiseControl(mode: .experimental_noise_canceling)
        } else if btDeviceInfo.noiseControl?.mode == .experimental_noise_canceling {
            let fallback = LastNoiseCancelingDataStore.shared.getLastMode(for: identify)
            setNoiseControl(mode: fallback == .experimental_noise_canceling ? .on : fallback)
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// `0x03A2` Find Earbuds Alert Sound (`0x100067bb0` & `0x100067dcc`)
    func setFindEarbuds(playing: Bool) {
        let cmd = GattCommandBuilder.build(command: 0x03A2, payload: [playing ? 0x01 : 0x00], includeCrc: false)
        enqueueCommand(cmd)
    }

    // MARK: - Frame Dispatch (`0x10004b694`)
    private func handleIncomingControlData(_ data: Data) {
        receiveBuffer.append(data)
        let rawFrames = OriginCommandParser.extractFrames(from: &receiveBuffer)
        for rawFrame in rawFrames {
            guard let frame = OriginCommandParser.parseFrame(rawFrame), frame.crcValid else {
                continue
            }
            dispatchParsedFrame(frame)
        }
    }

    private func dispatchParsedFrame(_ frame: GattCommandFrame) {
        let payload = frame.payload
        DispatchQueue.main.async {
            switch frame.command {
            case 0x0001:
                self.btDeviceInfo.btDeviceId = OriginCommandParser.parseTwoByteUpperHex(payload)
            case 0x0002:
                break
            case 0x0003:
                self.btDeviceInfo.firmwareVersion = OriginCommandParser.parseTwoByteUpperHex(payload)
            case 0x0004:
                self.btDeviceInfo.serialNumber = OriginCommandParser.parseLowerHexString(payload)
            case 0x0005:
                if let battery = OriginCommandParser.parseBatteryLevel(payload) {
                    self.btDeviceInfo.batteryLevel = battery
                }
            case 0x0101:
                if let nc = OriginCommandParser.parseNoiseControl(payload) {
                    self.btDeviceInfo.noiseControl = nc
                    if nc.mode == .experimental_noise_canceling {
                        if !ExperimentNoiseCancelingDataStore.shared.isEnabled(for: self.identify) {
                            ExperimentNoiseCancelingDataStore.shared.setEnabled(true, for: self.identify)
                        }
                    } else if nc.mode.isNoiseCancelingSubMode {
                        LastNoiseCancelingDataStore.shared.saveLastMode(nc.mode, for: self.identify)
                    }
                }
            case 0x0102:
                if let vol = OriginCommandParser.parseToneVolume(payload) {
                    self.btDeviceInfo.toneVolume = vol
                }
            case 0x0103:
                if let tc = OriginCommandParser.parseTouchControl(payload) {
                    self.btDeviceInfo.touchControl = tc
                }
            case 0x0104:
                if let codec = OriginCommandParser.parseCodec(payload) {
                    self.btDeviceInfo.codec = codec
                }
            case 0x0105:
                if let dual = OriginCommandParser.parseBool(payload) {
                    self.btDeviceInfo.dualConnection = dual
                }
            case 0x0106:
                if let lowLat = OriginCommandParser.parseBool(payload) {
                    self.btDeviceInfo.lowLatencyMode = lowLat
                }
            case 0x0107:
                if let eq = OriginCommandParser.parseEqIndex(payload) {
                    self.btDeviceInfo.eqIndex = eq
                }
            case 0x0108:
                if let gm = OriginCommandParser.parseBool(payload) {
                    self.btDeviceInfo.gameMode = gm
                }
            case 0x0109:
                if let inEar = OriginCommandParser.parseBool(payload) {
                    self.btDeviceInfo.inEarDetection = inEar
                }
            case 0x01E1:
                if let expWind = OriginCommandParser.parseBool(payload) {
                    self.btDeviceInfo.experimentWind = expWind
                }
            case 0x010A:
                if let ancTc = OriginCommandParser.parseAncTouchControl(payload) {
                    self.btDeviceInfo.ancTouchControl = ancTc
                }
            default:
                break
            }
            self.objectWillChange.send()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension LinkDevice: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            let uuidUpper = service.uuid.uuidString.uppercased()
            if uuidUpper == Self.originServiceUUIDString || uuidUpper == Self.otaServiceUUIDString {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            let uuidUpper = characteristic.uuid.uuidString.uppercased()
            switch uuidUpper {
            case Self.writeCharacteristicUUIDString:
                writeCharacteristic = characteristic
            case Self.notifyCharacteristicUUIDString:
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.otaCharacteristicUUIDString:
                otaCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                DispatchQueue.main.async {
                    self.isOTAReady = true
                }
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        let uuidUpper = characteristic.uuid.uuidString.uppercased()
        if uuidUpper == Self.notifyCharacteristicUUIDString && characteristic.isNotifying {
            queryAllState()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let uuidUpper = characteristic.uuid.uuidString.uppercased()
        if uuidUpper == Self.notifyCharacteristicUUIDString {
            handleIncomingControlData(value)
        } else if uuidUpper == Self.otaCharacteristicUUIDString {
            onOTADataReceived?(value)
        }
    }
}
