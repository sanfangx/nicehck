import Foundation
import Combine

/// Complete 12-Step BES BLE OTA State Machine (`0x100031ae0 .. 0x100035054`)
@MainActor
final class OTAManager: ObservableObject {
    @Published var state: OTAState = .initial
    @Published private(set) var isUpgrading: Bool = false

    private weak var linkDevice: LinkDevice?
    private var deviceMtu: Int = 200
    private var pendingExpectedType: OTAPackageType?
    private var responseContinuation: CheckedContinuation<Data, Error>?
    private var isAutoReconnectEnabled: Bool = false

    init(linkDevice: LinkDevice) {
        self.linkDevice = linkDevice
        setupNotificationHandler()
    }

    private func setupNotificationHandler() {
        linkDevice?.onOTADataReceived = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleOTAPacket(data)
            }
        }
    }

    private func handleOTAPacket(_ data: Data) {
        guard let (pkgType, payload) = OTACommandParser.parsePacket(data) else {
            return
        }
        if let expected = pendingExpectedType, pkgType == expected {
            pendingExpectedType = nil
            let cont = responseContinuation
            responseContinuation = nil
            cont?.resume(returning: payload)
        }
    }

    /// Send an OTA command and await its paired response with a 5.0-second timeout (`0x100034ab4`)
    private func sendCommandAndWaitForResponse(
        commandData: Data,
        expectedResponse: OTAPackageType,
        timeoutSeconds: Double = 5.0
    ) async throws -> Data {
        guard let linkDevice = linkDevice, linkDevice.connectionState == .connected else {
            throw OTAError.deviceNotConnected
        }

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
                pendingCont.resume(throwing: OTAError.timeout(expectedResponse))
            }
        }
    }

    func reset() {
        state = .initial
        isUpgrading = false
        pendingExpectedType = nil
        responseContinuation = nil
    }

    /// Execute the 12-step BES OTA firmware upgrade (`0x100031ae0`)
    func startOTA(imageData: Data) async {
        guard !isUpgrading else { return }
        guard let linkDevice = linkDevice, linkDevice.connectionState == .connected else {
            state = OTAState(
                step: .error,
                progress: 0,
                statusTextKey: "update_failed",
                error: NSLocalizedString("device_not_connected", comment: "")
            )
            return
        }
        guard imageData.count >= 64 else {
            state = OTAState(
                step: .error,
                progress: 0,
                statusTextKey: "update_failed",
                error: OTAError.invalidFirmwareImage.localizedDescription
            )
            return
        }

        setupNotificationHandler()
        isUpgrading = true
        deviceMtu = 200
        state = OTAState(step: .started, progress: 0.0, statusTextKey: "getting_ota_info", error: nil)

        do {
            // Step 1: 0x99 -> 0x9A getProtocol
            _ = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.getProtocol(),
                expectedResponse: .getProtocolRes
            )

            // Step 2: 0x9D -> 0x9E setUpgradeType
            state.statusTextKey = "setting_upgrade_type"
            _ = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.setUpgradeType(),
                expectedResponse: .setUpgradeTypeRes
            )

            // Step 3: 0x8E -> 0x8F getCurrentVersion
            state.statusTextKey = "getting_ota_info"
            let verPayload = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.getCurrentVersion(),
                expectedResponse: .getCurrentVersionRes
            )
            _ = OTACommandParser.parseDeviceInfo(verPayload)

            // Step 4: 0x97 -> 0x98 setUser
            _ = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.setUser(),
                expectedResponse: .setUserRes
            )

            // Step 5: 0x9B -> 0x9C getRoleSwitchRandomId (allow 3.0s reconnect if role-switch occurs)
            state.statusTextKey = "getting_role_switch_id"
            isAutoReconnectEnabled = true
            do {
                _ = try await sendCommandAndWaitForResponse(
                    commandData: OTACommand.getRoleSwitchRandomId(),
                    expectedResponse: .getRoleSwitchRandomIdRes
                )
            } catch {
                // Wait 3.0s for TWS role switch reconnection if needed (`0x100031df4`)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if linkDevice.connectionState != .connected {
                    BluetoothManager.shared.connect(linkDevice)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            isAutoReconnectEnabled = false

            // Step 6: 0x90 -> 0x91 selectSide
            state.statusTextKey = "selecting_device_side"
            _ = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.selectSide(),
                expectedResponse: .selectSideRes
            )

            // Step 7: 0x8C -> 0x8D getTransmissionResumingAtBreakPoint
            state.statusTextKey = "preparing_data_transmission"
            guard let resumeCmd = OTACommand.getTransmissionResumingAtBreakPoint(imageData: imageData) else {
                throw OTAError.invalidFirmwareImage
            }
            let resumePayload = try await sendCommandAndWaitForResponse(
                commandData: resumeCmd,
                expectedResponse: .getTransmissionResumingAtBreakPointRes
            )
            if let resumeInfo = OTACommandParser.parseResumePacket(resumePayload),
               let negotiatedMtu = resumeInfo.negotiatedMtu,
               negotiatedMtu >= 32 {
                deviceMtu = negotiatedMtu
            }

            // Step 8: 0x80 -> 0x81 fetchOTA
            _ = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.fetchOTA(imageData: imageData),
                expectedResponse: .fetchOTARes
            )

            // Step 9: 0x86 -> 0x87 config
            state.statusTextKey = "configuring_ota_params"
            guard let configCmd = OTACommand.config(imageData: imageData) else {
                throw OTAError.invalidFirmwareImage
            }
            _ = try await sendCommandAndWaitForResponse(
                commandData: configCmd,
                expectedResponse: .configRes
            )

            // Step 10: 32KB segmented streaming (`0x85` chunks spaced by 25ms + `0x82 -> 0x83` per segment)
            state.statusTextKey = "sending_firmware_data"
            let segments = OTACommand.splitImageIntoSegments(imageData: imageData, deviceMtu: deviceMtu)
            let totalBytes = Float(max(1, imageData.count))
            var sentBytes = 0

            for segment in segments {
                for chunk in segment.chunks {
                    guard linkDevice.connectionState == .connected else {
                        throw OTAError.deviceNotConnected
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
                    try await Task.sleep(nanoseconds: 25_000_000) // 25ms (`0x100032638`)
                }

                // Verify 32KB segment CRC (`0x82 -> 0x83`)
                let segVerifyRes = try await sendCommandAndWaitForResponse(
                    commandData: OTACommand.segmentCrcVerify(segmentCrc: segment.crc32),
                    expectedResponse: .segmentCrcVerifyRes
                )
                guard segVerifyRes.first == 0x01 else {
                    throw OTAError.crcVerificationFailed
                }
            }

            // Step 11: 0x88 -> 0x84 imageCrcVerify
            state.statusTextKey = "verifying_firmware_integrity"
            let imageVerifyRes = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.imageCrcVerify(),
                expectedResponse: .imageCrcVerifyRes,
                timeoutSeconds: 8.0
            )
            guard imageVerifyRes.first == 0x01 else {
                throw OTAError.crcVerificationFailed
            }

            // Step 12: 0x92 -> 0x93 imageOverwritingConfirmation
            state.statusTextKey = "confirming_firmware_installation"
            let confirmRes = try await sendCommandAndWaitForResponse(
                commandData: OTACommand.imageOverwritingConfirmation(),
                expectedResponse: .imageOverwritingConfirmationRes,
                timeoutSeconds: 8.0
            )
            guard confirmRes.first == 0x01 else {
                throw OTAError.unexpectedResponse
            }

            state = OTAState(
                step: .completed,
                progress: 1.0,
                statusTextKey: "update_completed",
                error: nil
            )
            isUpgrading = false
            BluetoothManager.shared.scheduleDeviceRestartTimer(for: linkDevice)
        } catch {
            isUpgrading = false
            state = OTAState(
                step: .error,
                progress: state.progress,
                statusTextKey: "update_failed",
                error: error.localizedDescription
            )
        }
    }
}
