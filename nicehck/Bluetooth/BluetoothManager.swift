import Foundation
import CoreBluetooth
import AVFoundation
import Combine

/// Observes system Bluetooth audio route changes (`0x10000c14c`)
final class AudioRouteManager: ObservableObject {
    static let shared = AudioRouteManager()

    @Published private(set) var isBluetoothAudioConnected: Bool = false
    @Published private(set) var connectedPortName: String?
    var onBluetoothAudioConnected: (() -> Void)?

    private init() {
        refreshCurrentRoute()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        let wasConnected = isBluetoothAudioConnected
        refreshCurrentRoute()
        if !wasConnected && isBluetoothAudioConnected {
            onBluetoothAudioConnected?()
        }
    }

    func refreshCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let btPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        if let port = session.currentRoute.outputs.first(where: { btPorts.contains($0.portType) }) {
            DispatchQueue.main.async {
                self.isBluetoothAudioConnected = true
                self.connectedPortName = port.portName
            }
        } else {
            DispatchQueue.main.async {
                self.isBluetoothAudioConnected = false
                self.connectedPortName = nil
            }
        }
    }
}

final class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published private(set) var linkDevices: [LinkDevice] = []
    @Published private(set) var discoveredDevices: [LinkDevice] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var authorization: CBManagerAuthorization = CBManager.authorization
    @Published private(set) var centralState: CBManagerState = .unknown

    private var centralManager: CBCentralManager!
    private var reconnectTimer: Timer?
    private var restartTimer: Timer?
    private var deviceCancellables: [String: AnyCancellable] = [:]
    private let repository = ConnectedDeviceRepository.shared

    var isBluetoothPermissionDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    override private init() {
        super.init()
        loadSavedDevices()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        AudioRouteManager.shared.onBluetoothAudioConnected = { [weak self] in
            self?.checkSystemConnectedGattDevices()
            self?.reconnectDisconnectedSavedDevices()
        }
        startPeriodicReconnectTimer()
    }

    private func loadSavedDevices() {
        for saved in repository.devices {
            guard let model = DeviceManager.shared.device(forId: saved.deviceId) else { continue }
            _ = getOrCreateLinkDevice(identify: saved.identify, device: model, peripheral: nil, isSaved: true)
        }
    }

    @discardableResult
    private func getOrCreateLinkDevice(
        identify: String,
        device: Device,
        peripheral: CBPeripheral?,
        isSaved: Bool
    ) -> LinkDevice {
        if let existing = linkDevices.first(where: { $0.identify.caseInsensitiveCompare(identify) == .orderedSame }) {
            if let p = peripheral {
                existing.attachPeripheral(p)
            }
            return existing
        }

        let ld = LinkDevice(identify: identify, device: device, peripheral: peripheral)
        observeLinkDevice(ld)

        if isSaved {
            linkDevices.append(ld)
        }
        return ld
    }

    private func observeLinkDevice(_ ld: LinkDevice) {
        deviceCancellables[ld.identify] = ld.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    // MARK: - System Connected GATT Retrieval (`0x10003b03c` & `0x10003cf80`)
    func checkSystemConnectedGattDevices() {
        guard centralManager.state == .poweredOn else { return }

        // 1. Check connected peripherals exposing Origin Control or OTA services
        let systemConnected = centralManager.retrieveConnectedPeripherals(withServices: [
            LinkDevice.originServiceUUID,
            LinkDevice.otaServiceUUID
        ])
        for peripheral in systemConnected {
            let name = peripheral.name ?? ""
            let matchedModel = DeviceManager.shared.matchSupportedDevice(peripheralName: name)
                ?? DeviceManager.shared.devices.first
            guard let model = matchedModel else { continue }
            let idStr = peripheral.identifier.uuidString
            let ld = getOrCreateLinkDevice(identify: idStr, device: model, peripheral: peripheral, isSaved: true)
            repository.saveDevice(identify: idStr, deviceId: model.id)
            if ld.connectionState != .connected && ld.connectionState != .connecting {
                connect(ld)
            }
        }

        // 2. Also retrieve saved peripherals by UUID identifier
        let uuids = linkDevices.compactMap { UUID(uuidString: $0.identify) }
        if !uuids.isEmpty {
            let retrieved = centralManager.retrievePeripherals(withIdentifiers: uuids)
            for peripheral in retrieved {
                let idStr = peripheral.identifier.uuidString
                if let ld = linkDevices.first(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }) {
                    ld.attachPeripheral(peripheral)
                    if ld.connectionState == .disconnected {
                        connect(ld)
                    }
                }
            }
        }
    }

    /// Sync disconnected state (`0x10003bd50`)
    func syncDisconnectedDevices() {
        guard centralManager.state == .poweredOn else { return }
        for ld in linkDevices {
            if let p = ld.peripheral, p.state == .disconnected, ld.connectionState == .connected {
                ld.handleDisconnected()
            }
        }
    }

    // MARK: - Scanning & Connection
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        checkSystemConnectedGattDevices()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.stopScan()
        isScanning = false
    }

    func connect(_ linkDevice: LinkDevice) {
        guard centralManager.state == .poweredOn else { return }
        if linkDevice.peripheral == nil, let uuid = UUID(uuidString: linkDevice.identify) {
            if let p = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
                linkDevice.attachPeripheral(p)
            }
        }
        guard let peripheral = linkDevice.peripheral else {
            startScanning()
            return
        }

        if !linkDevices.contains(where: { $0.identify.caseInsensitiveCompare(linkDevice.identify) == .orderedSame }) {
            linkDevices.append(linkDevice)
            observeLinkDevice(linkDevice)
        }
        repository.saveDevice(identify: linkDevice.identify, deviceId: linkDevice.device.id)
        linkDevice.connectionState = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(_ linkDevice: LinkDevice) {
        guard let peripheral = linkDevice.peripheral else {
            linkDevice.handleDisconnected()
            return
        }
        linkDevice.connectionState = .disconnecting
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func removeDevice(_ linkDevice: LinkDevice) {
        if let peripheral = linkDevice.peripheral,
           peripheral.state == .connected || peripheral.state == .connecting {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        repository.removeDevice(identify: linkDevice.identify)
        deviceCancellables.removeValue(forKey: linkDevice.identify)
        linkDevices.removeAll { $0.identify.caseInsensitiveCompare(linkDevice.identify) == .orderedSame }
    }

    // MARK: - Reconnect Timers (`3.0s` periodic at `0x10003b9a8`, `10.0s` restart at `0x10003bc1c`)
    private func startPeriodicReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.syncDisconnectedDevices()
            self?.checkSystemConnectedGattDevices()
        }
    }

    func reconnectDisconnectedSavedDevices() {
        guard centralManager.state == .poweredOn else { return }
        for ld in linkDevices where ld.connectionState == .disconnected {
            connect(ld)
        }
    }

    func scheduleDeviceRestartTimer(for linkDevice: LinkDevice) {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.checkSystemConnectedGattDevices()
            self?.connect(linkDevice)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        centralState = central.state
        authorization = CBManager.authorization
        if central.state == .poweredOn {
            checkSystemConnectedGattDevices()
            reconnectDisconnectedSavedDevices()
        } else {
            isScanning = false
            for ld in linkDevices {
                ld.handleDisconnected()
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? ""
        guard let matchedModel = DeviceManager.shared.matchSupportedDevice(peripheralName: localName) else {
            return
        }

        let idStr = peripheral.identifier.uuidString
        if let savedDevice = linkDevices.first(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }) {
            savedDevice.attachPeripheral(peripheral)
            if savedDevice.connectionState == .disconnected {
                connect(savedDevice)
            }
            return
        }

        if !discoveredDevices.contains(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }) {
            let candidate = LinkDevice(identify: idStr, device: matchedModel, peripheral: peripheral)
            observeLinkDevice(candidate)
            discoveredDevices.append(candidate)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let idStr = peripheral.identifier.uuidString
        if let ld = linkDevices.first(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame })
            ?? discoveredDevices.first(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }) {
            if !linkDevices.contains(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }) {
                linkDevices.append(ld)
            }
            discoveredDevices.removeAll { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }
            repository.saveDevice(identify: idStr, deviceId: ld.device.id)
            ld.handleConnected()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let idStr = peripheral.identifier.uuidString
        if let ld = linkDevices.first(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }) {
            ld.handleDisconnected()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let idStr = peripheral.identifier.uuidString
        if let ld = linkDevices.first(where: { $0.identify.caseInsensitiveCompare(idStr) == .orderedSame }) {
            ld.handleDisconnected()
        }
    }
}
