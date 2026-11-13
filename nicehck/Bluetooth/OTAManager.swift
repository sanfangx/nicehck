import Foundation
import Combine

/// Complete 12-Step BES BLE OTA State Machine (`0x100031ae0 .. 0x100035054`)
@MainActor
final class OTAManager: ObservableObject {
    @Published var state: OTAState = .initial
    @Published private(set) var isUpgrading: Bool = false
    @Published private(set) var diagnosticLogs: [String] = []
    @Published private(set) var currentStepDetail: String = ""

    private weak var linkDevice: LinkDevice?
    private var deviceMtu: Int = 200
    private var pendingExpectedType: OTAPackageType?
    private var responseContinuation: CheckedContinuation<Data, Error>?
    private var otaReceiveBuffer = Data()
    private var isRoleSwitchWindowActive: Bool = false

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var formattedDiagnosticLog: String {
        diagnosticLogs.joined(separator: "\n")
    }

    init(linkDevice: LinkDevice) {
        self.linkDevice = linkDevice
        setupCallbacks()
    }

    private func setupCallbacks() {
        linkDevice?.onOTADataReceived = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleOTAData(data)
            }
        }
        linkDevice?.onDisconnected = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleUnexpectedDisconnect()
            }
        }
    }

    func clearLogs() {
        diagnosticLogs.removeAll()
        currentStepDetail = ""
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        diagnosticLogs.append(line)
        if diagnosticLogs.count > 600 {
            diagnosticLogs.removeFirst(diagnosticLogs.count - 600)
        }
    }

    private func formatHex(_ data: Data, limit: Int = 48) -> String {
        let slice = data.prefix(limit)
        let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
        if data.count > limit {
            return "\(hex) ... (\(data.count) B)"
        }
        return hex
    }

    private func handleUnexpectedDisconnect() {
        otaReceiveBuffer.removeAll()
        guard isUpgrading else { return }
        if isRoleSwitchWindowActive {
            appendLog("BLE disconnected during role-switch window (tolerable)")
            return
        }
        appendLog("ERROR: BLE disconnected mid-OTA")
        failPendingContinuation(with: OTAError.disconnectedDuringUpgrade)
    }

    private func failPendingContinuation(with error: Error) {
        guard let continuation = responseContinuation else { return }
        pendingExpectedType = nil
        responseContinuation = nil
        continuation.resume(throwing: error)
    }

    private func handleOTAData(_ chunk: Data) {
        guard isUpgrading || responseContinuation != nil else { return }
        otaReceiveBuffer.append(chunk)
        let packets = OTACommandParser.extractPackets(from: &otaReceiveBuffer)
        for (pkgType, payload) in packets {
            let expectedHex = pendingExpectedType.map { String(format: "0x%02X", $0.rawValue) } ?? "none"
            appendLog(
                String(
                    format: "RX 0x%02X (%d B, expect %@): %@",
                    pkgType.rawValue,
                    payload.count,
                    expectedHex,
                    formatHex(payload)
                )
            )
            if let expected = pendingExpectedType, pkgType == expected {
                pendingExpectedType = nil
                let cont = responseContinuation
                responseContinuation = nil
                cont?.resume(returning: payload)
            }
        }
    }

    private func sendFireAndSleep(
        stepName: String,
        commandData: Data,
        sleepSeconds: Double
    ) async throws {
        guard let linkDevice = linkDevice, linkDevice.connectionState == .connected else {
            throw OTAError.disconnectedDuringUpgrade
        }
        appendLog("TX [\(stepName)]: \(formatHex(commandData))")
        guard linkDevice.writeOTAData(commandData) else {
            throw OTAError.characteristicUnavailable
        }
        try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
    }

    /// Send an OTA command and await its paired response with timeout (`0x100034ab4`)
    private func sendCommandAndWaitForResponse(
        stepName: String,
        commandData: Data,
        expectedResponse: OTAPackageType,
        timeoutSeconds: Double = 5.0
    ) async throws -> Data {
        guard let linkDevice = linkDevice, linkDevice.connectionState == .connected else {
            throw OTAError.disconnectedDuringUpgrade
        }

        appendLog("TX [\(stepName)]: \(formatHex(commandData))")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.pendingExpectedType = expectedResponse
            self.responseContinuation = continuation

            guard linkDevice.writeOTAData(commandData) else {
                self.pendingExpectedType = nil
                self.responseContinuation = nil
                continuation.resume(throwing: OTAError.characteristicUnavailable)
                return
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard let self = self,
                      self.pendingExpectedType == expectedResponse,
                      let pendingCont = self.responseContinuation else {
                    return
                }
                self.pendingExpectedType = nil
                self.responseContinuation = nil
                self.appendLog(String(format: "TIMEOUT waiting for 0x%02X after %.1fs [%@]", expectedResponse.rawValue, timeoutSeconds, stepName))
                pendingCont.resume(throwing: OTAError.timeout(expectedResponse))
            }
        }
    }

    func reset() {
        failPendingContinuation(with: OTAError.disconnectedDuringUpgrade)
        otaReceiveBuffer.removeAll()
        isRoleSwitchWindowActive = false
        state = .initial
        isUpgrading = false
        currentStepDetail = ""
    }

    /// Execute the 12-step BES OTA firmware upgrade (`0x100031ae0`)
    func startOTA(imageData: Data) async {
        guard !isUpgrading else { return }
        diagnosticLogs.removeAll()
        otaReceiveBuffer.removeAll()
        isRoleSwitchWindowActive = false

        guard let linkDevice = linkDevice, linkDevice.connectionState == .connected else {
            let msg = NSLocalizedString("device_not_connected", comment: "")
            appendLog("ABORT: \(msg)")
            state = OTAState(step: .error, progress: 0, statusTextKey: "update_failed", error: msg)
            return
        }
        guard linkDevice.isOTAReady else {
            let msg = NSLocalizedString("not_ready_for_update", comment: "")
            appendLog("ABORT: isOTAReady == false")
            state = OTAState(step: .error, progress: 0, statusTextKey: "update_failed", error: msg)
            return
        }
        guard imageData.count >= 64 else {
            let msg = OTAError.invalidFirmwareImage.localizedDescription
            appendLog("ABORT: image too small (\(imageData.count) B)")
            state = OTAState(step: .error, progress: 0, statusTextKey: "update_failed", error: msg)
            return
        }

        setupCallbacks()
        isUpgrading = true
        deviceMtu = 200
        let tailText = String(bytes: imageData.suffix(min(32, imageData.count)), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "<non-ascii>"
        appendLog(
            "START OTA: image=\(imageData.count) B, tail='\(tailText)', " +
            "devVer=\(linkDevice.btDeviceInfo.firmwareVersion ?? "nil") (raw \(linkDevice.btDeviceInfo.rawFirmwareVersionHex ?? "nil")), " +
            "maxWrite=\(linkDevice.maxOTAWriteLength) (\(linkDevice.otaWriteTypeName))"
        )
        state = OTAState(step: .started, progress: 0.0, statusTextKey: "getting_ota_info", error: nil)

        do {
            // Step 1: 0x99 -> 0x9A getProtocol (switches BES _relay_ota_data into 5-byte TLV mode)
            currentStepDetail = "Step 1/12: getProtocol (0x99)"
            _ = try await sendCommandAndWaitForResponse(
                stepName: "1 getProtocol",
                commandData: OTACommand.getProtocol(),
                expectedResponse: .getProtocolRes
            )

            // Step 2: 0x97 -> 0x98 setUser (IPA executes 0x97 before 0x8E)
            currentStepDetail = "Step 2/12: setUser (0x97)"
            _ = try await sendCommandAndWaitForResponse(
                stepName: "2 setUser",
                commandData: OTACommand.setUser(),
                expectedResponse: .setUserRes
            )

            // Step 3: 0x8E -> 0x8F getCurrentVersion
            currentStepDetail = "Step 3/12: getCurrentVersion (0x8E)"
            state.statusTextKey = "getting_ota_info"
            let verPayload = try await sendCommandAndWaitForResponse(
                stepName: "3 getCurrentVersion",
                commandData: OTACommand.getCurrentVersion(),
                expectedResponse: .getCurrentVersionRes
            )
            if let otaVer = OTACommandParser.parseDeviceInfo(verPayload) {
                appendLog(
                    String(
                        format: "Device OTA version: type=0x%02X L=%@ R=%@",
                        otaVer.deviceType,
                        formatHex(otaVer.leftOrStereoVersion),
                        formatHex(otaVer.rightVersion)
                    )
                )
            }

            // Step 4: 0x9D setUpgradeType ([0x01], fire + 1.0s sleep — BES switch skips 0x9D)
            currentStepDetail = "Step 4/12: setUpgradeType (0x9D)"
            state.statusTextKey = "setting_upgrade_type"
            try await sendFireAndSleep(
                stepName: "4 setUpgradeType",
                commandData: OTACommand.setUpgradeType(),
                sleepSeconds: 1.0
            )

            // Step 5: 0x9B getRoleSwitchRandomId (empty payload, fire + 1.0s sleep — BES switch skips 0x9B)
            currentStepDetail = "Step 5/12: roleSwitch (0x9B)"
            state.statusTextKey = "getting_role_switch_id"
            isRoleSwitchWindowActive = true
            try await sendFireAndSleep(
                stepName: "5 roleSwitch",
                commandData: OTACommand.getRoleSwitchRandomId(),
                sleepSeconds: 1.0
            )
            if linkDevice.connectionState != .connected || !linkDevice.isOTAReady {
                appendLog("Waiting for reconnection/OTA characteristic readiness after 0x9B...")
                if linkDevice.connectionState != .connected {
                    BluetoothManager.shared.connect(linkDevice)
                }
                for _ in 0..<25 {
                    if linkDevice.connectionState == .connected && linkDevice.isOTAReady {
                        break
                    }
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                guard linkDevice.connectionState == .connected && linkDevice.isOTAReady else {
                    throw OTAError.disconnectedDuringUpgrade
                }
            }
            isRoleSwitchWindowActive = false

            // Step 6: 0x90 -> 0x91 selectSide
            currentStepDetail = "Step 6/12: selectSide (0x90)"
            state.statusTextKey = "selecting_device_side"
            let sideRes = try await sendCommandAndWaitForResponse(
                stepName: "6 selectSide",
                commandData: OTACommand.selectSide(),
                expectedResponse: .selectSideRes
            )
            guard sideRes.first == 0x01 else {
                throw OTAError.upgradeRejected("selectSide rejected (0x91: \(formatHex(sideRes)))")
            }

            // Step 7: 0x8C -> 0x8D getTransmissionResumingAtBreakPoint
            currentStepDetail = "Step 7/12: resumeCheck (0x8C)"
            state.statusTextKey = "preparing_data_transmission"
            let resumePayload = try await sendCommandAndWaitForResponse(
                stepName: "7 resumeCheck",
                commandData: OTACommand.getTransmissionResumingAtBreakPoint(),
                expectedResponse: .getTransmissionResumingAtBreakPointRes
            )
            if let resumeInfo = OTACommandParser.parseResumePacket(resumePayload) {
                appendLog("Resume info: breakpoint=\(resumeInfo.breakpoint), mtu=\(resumeInfo.negotiatedMtu.map(String.init) ?? "nil")")
                if let negotiatedMtu = resumeInfo.negotiatedMtu, negotiatedMtu >= 32 {
                    deviceMtu = negotiatedMtu
                }
            }

            // Step 8: 0x80 -> 0x81 fetchOTA
            currentStepDetail = "Step 8/12: fetchOTA (0x80)"
            let fetchPayload = try await sendCommandAndWaitForResponse(
                stepName: "8 fetchOTA",
                commandData: OTACommand.fetchOTA(imageData: imageData),
                expectedResponse: .fetchOTARes
            )
            let fetchResult = OTACommandParser.parseFetchOTAResponse(fetchPayload)
            guard fetchResult.accepted else {
                throw OTAError.upgradeRejected("fetchOTA rejected (0x81: \(formatHex(fetchPayload)))")
            }
            if let negotiatedMtu = fetchResult.negotiatedMtu, negotiatedMtu >= 32 {
                deviceMtu = negotiatedMtu
            }

            // Step 9: 0x86 -> 0x87 config (92-byte payload ending with CRC32)
            currentStepDetail = "Step 9/12: config (0x86)"
            state.statusTextKey = "configuring_ota_params"
            guard let configCmd = OTACommand.config(imageData: imageData) else {
                throw OTAError.invalidFirmwareImage
            }
            let configRes = try await sendCommandAndWaitForResponse(
                stepName: "9 config",
                commandData: configCmd,
                expectedResponse: .configRes
            )
            guard configRes.first == 0x01 else {
                throw OTAError.upgradeRejected("config rejected (0x87: \(formatHex(configRes)))")
            }

            // Step 10: 32KB segmented streaming (`0x85` chunks spaced by 13ms + `0x82 -> 0x83` per segment)
            let attChunkCap = max(8, linkDevice.maxOTAWriteLength - 5)
            let mtuChunkCap = max(8, deviceMtu - 10)
            let maxPayload = min(attChunkCap, mtuChunkCap, OTACommand.maxDataChunkPayload)
            let segments = OTACommand.splitImageIntoSegments(imageData: imageData, maxChunkPayload: maxPayload)
            let chunkBytes = segments.first?.chunks.first?.count ?? 0
            appendLog(
                "Streaming \(segments.count) segments: deviceMtu=\(deviceMtu), " +
                "maxATT=\(linkDevice.maxOTAWriteLength), chunkSize=\(chunkBytes) B (\(linkDevice.otaWriteTypeName))"
            )

            state.statusTextKey = "sending_firmware_data"
            let totalBytes = Float(max(1, imageData.count))
            var sentBytes = 0

            for segment in segments {
                currentStepDetail = "Step 10/12: segment \(segment.index + 1)/\(segments.count)"
                for chunk in segment.chunks {
                    guard linkDevice.connectionState == .connected else {
                        throw OTAError.disconnectedDuringUpgrade
                    }
                    let packet = OTACommand.dataPacket(chunk: chunk)
                    guard linkDevice.writeOTAData(packet) else {
                        throw OTAError.characteristicUnavailable
                    }
                    sentBytes += chunk.count
                    let currentProgress = min(0.98, Float(sentBytes) / totalBytes)
                    state = OTAState(
                        step: .progress,
                        progress: currentProgress,
                        statusTextKey: "sending_firmware_data",
                        error: nil
                    )
                    try await Task.sleep(nanoseconds: 13_000_000) // 13ms (`0x100032638`)
                }

                // Verify 32KB segment CRC (`0x82 -> 0x83`)
                let segVerifyRes = try await sendCommandAndWaitForResponse(
                    stepName: "10 segCrc #\(segment.index + 1)/\(segments.count)",
                    commandData: OTACommand.segmentCrcVerify(segmentCrc: segment.crc32),
                    expectedResponse: .segmentCrcVerifyRes,
                    timeoutSeconds: 8.0
                )
                guard segVerifyRes.first == 0x01 else {
                    throw OTAError.crcVerificationFailed(
                        "Segment #\(segment.index + 1) CRC rejected (0x83: \(formatHex(segVerifyRes)))"
                    )
                }
            }

            // Step 11: 1.0s settle (`0x1000309c0`) + 0x88 -> 0x84 imageCrcVerify
            currentStepDetail = "Step 11/12: imageCrcVerify (0x88)"
            state.statusTextKey = "verifying_firmware_integrity"
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let imageVerifyRes = try await sendCommandAndWaitForResponse(
                stepName: "11 imageCrcVerify",
                commandData: OTACommand.imageCrcVerify(),
                expectedResponse: .imageCrcVerifyRes,
                timeoutSeconds: 15.0
            )
            guard imageVerifyRes.first == 0x01 else {
                throw OTAError.crcVerificationFailed(
                    "Image CRC rejected (0x84: \(formatHex(imageVerifyRes)))"
                )
            }

            // Step 12: 0x92 -> 0x93 imageOverwritingConfirmation
            currentStepDetail = "Step 12/12: overwriteConfirm (0x92)"
            state.statusTextKey = "confirming_firmware_installation"
            let confirmRes = try await sendCommandAndWaitForResponse(
                stepName: "12 overwriteConfirm",
                commandData: OTACommand.imageOverwritingConfirmation(),
                expectedResponse: .imageOverwritingConfirmationRes,
                timeoutSeconds: 10.0
            )
            guard confirmRes.first == 0x01 else {
                throw OTAError.unexpectedResponse(
                    "0x93: \(formatHex(confirmRes))"
                )
            }

            currentStepDetail = "Completed"
            appendLog("OTA COMPLETED SUCCESSFULLY; scheduling restart timer")
            state = OTAState(
                step: .completed,
                progress: 1.0,
                statusTextKey: "update_completed",
                error: nil
            )
            isUpgrading = false
            BluetoothManager.shared.scheduleDeviceRestartTimer(for: linkDevice)
        } catch {
            isRoleSwitchWindowActive = false
            isUpgrading = false
            currentStepDetail = "Failed: \(error.localizedDescription)"
            appendLog("OTA FAILED: \(error.localizedDescription)")
            state = OTAState(
                step: .error,
                progress: state.progress,
                statusTextKey: "update_failed",
                error: error.localizedDescription
            )
        }
    }
}
