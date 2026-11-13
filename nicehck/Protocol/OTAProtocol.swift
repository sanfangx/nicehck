import Foundation

/// Exact 25 cases of `nicehck.OTAPackageType` (`0x1000ae5b2`)
enum OTAPackageType: UInt8, CaseIterable, Equatable {
    case getProtocol = 0x99
    case getProtocolRes = 0x9A
    case setUser = 0x97
    case setUserRes = 0x98
    case getCurrentVersion = 0x8E
    case getCurrentVersionRes = 0x8F
    case setUpgradeType = 0x9D
    case setUpgradeTypeRes = 0x9E
    case getRoleSwitchRandomId = 0x9B
    case getRoleSwitchRandomIdRes = 0x9C
    case selectSide = 0x90
    case selectSideRes = 0x91
    case getTransmissionResumingAtBreakPoint = 0x8C
    case getTransmissionResumingAtBreakPointRes = 0x8D
    case fetchOTA = 0x80
    case fetchOTARes = 0x81
    case config = 0x86
    case configRes = 0x87
    case data = 0x85
    case segmentCrcVerify = 0x82
    case segmentCrcVerifyRes = 0x83
    case imageCrcVerify = 0x88
    case imageCrcVerifyRes = 0x84
    case imageOverwritingConfirmation = 0x92
    case imageOverwritingConfirmationRes = 0x93

    var expectedResponse: OTAPackageType? {
        switch self {
        case .getProtocol: return .getProtocolRes
        case .setUser: return .setUserRes
        case .getCurrentVersion: return .getCurrentVersionRes
        case .setUpgradeType: return .setUpgradeTypeRes
        case .getRoleSwitchRandomId: return .getRoleSwitchRandomIdRes
        case .selectSide: return .selectSideRes
        case .getTransmissionResumingAtBreakPoint: return .getTransmissionResumingAtBreakPointRes
        case .fetchOTA: return .fetchOTARes
        case .config: return .configRes
        case .segmentCrcVerify: return .segmentCrcVerifyRes
        case .imageCrcVerify: return .imageCrcVerifyRes
        case .imageOverwritingConfirmation: return .imageOverwritingConfirmationRes
        default: return nil
        }
    }
}

struct OTADeviceInfo: Equatable {
    let deviceType: UInt8
    let leftOrStereoVersion: Data
    let rightVersion: Data
}

struct ResumePacket: Equatable {
    let breakpoint: UInt32
    let randomCode: Data
    let crc32: UInt32
    let negotiatedMtu: Int?
}

struct ImageSegment {
    let index: Int
    let data: Data
    let crc32: UInt32
    let chunks: [Data]
}

enum OTAStep: String, Equatable {
    case unstart
    case started
    case progress
    case completed
    case error
}

struct OTAState: Equatable {
    var step: OTAStep
    var progress: Float
    var statusTextKey: String
    var error: String?

    static let initial = OTAState(
        step: .unstart,
        progress: 0,
        statusTextKey: "preparation_stage",
        error: nil
    )
}

enum OTAError: LocalizedError {
    case deviceNotConnected
    case disconnectedDuringUpgrade
    case characteristicUnavailable
    case invalidFirmwareImage
    case timeout(OTAPackageType)
    case unexpectedResponse(String)
    case crcVerificationFailed(String)
    case upgradeRejected(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotConnected:
            return NSLocalizedString("device_not_connected", comment: "")
        case .disconnectedDuringUpgrade:
            return NSLocalizedString("ota_error_disconnected", comment: "")
        case .characteristicUnavailable:
            return NSLocalizedString("not_ready_for_update", comment: "")
        case .invalidFirmwareImage:
            return NSLocalizedString("ota_error_invalid_image", comment: "")
        case .timeout(let type):
            return String(
                format: "%@ (cmd 0x%02X)",
                NSLocalizedString("update_failed", comment: ""),
                type.rawValue
            )
        case .unexpectedResponse(let detail):
            return "\(NSLocalizedString("update_failed", comment: "")) (\(detail))"
        case .crcVerificationFailed(let detail):
            return detail
        case .upgradeRejected(let msg):
            return msg
        }
    }
}

enum OTACommand {
    /// ASCII "BEST" (`[0x42, 0x45, 0x53, 0x54]`, `0x1000f3bf8`)
    static let magicCode: [UInt8] = [0x42, 0x45, 0x53, 0x54]

    /// Standard IEEE 802.3 CRC-32 (`0x10002a6b0`)
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }

    static func appendUInt32LE(_ value: UInt32, to array: inout [UInt8]) {
        array.append(UInt8(value & 0xFF))
        array.append(UInt8((value >> 8) & 0xFF))
        array.append(UInt8((value >> 16) & 0xFF))
        array.append(UInt8((value >> 24) & 0xFF))
    }

    /// 5-byte header + payload (`0x100029d50`)
    static func createCommand(type: OTAPackageType, payload: [UInt8]) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(5 + payload.count)
        bytes.append(type.rawValue)
        appendUInt32LE(UInt32(payload.count), to: &bytes)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    /// Step 1: `0x99` getProtocol (`0x100031ba4`)
    static func getProtocol() -> Data {
        createCommand(type: .getProtocol, payload: [0x00, 0x00, 0x00, 0x01])
    }

    /// Step 2: `0x97` setUser (`0x100031d04`, `0x1000f3c88`)
    static func setUser() -> Data {
        createCommand(type: .setUser, payload: [0x01])
    }

    /// Step 3: `0x8E` getCurrentVersion (`0x100029fb4`)
    static func getCurrentVersion() -> Data {
        createCommand(type: .getCurrentVersion, payload: magicCode)
    }

    /// Step 4: `0x9D` setUpgradeType (`0x100031c20`, `0x1000f3cb8` — fire-and-forget + 1.0s sleep)
    static func setUpgradeType() -> Data {
        createCommand(type: .setUpgradeType, payload: [0x01])
    }

    /// Step 5: `0x9B` getRoleSwitchRandomId (`0x100031df4` — empty payload, fire-and-forget + 1.0s sleep)
    static func getRoleSwitchRandomId() -> Data {
        createCommand(type: .getRoleSwitchRandomId, payload: [])
    }

    /// Step 6: `0x90` selectSide (`0x100032090`, `0x1000f3ce8`)
    static func selectSide() -> Data {
        createCommand(type: .selectSide, payload: [0x00])
    }

    /// Step 7: `0x8C` getTransmissionResumingAtBreakPoint (`0x10002a054`, 44-byte payload)
    static func getTransmissionResumingAtBreakPoint() -> Data {
        var checkData = [UInt8](repeating: 0, count: 32)
        appendUInt32LE(0x04030201, to: &checkData)
        let checkCrc = crc32(Data(checkData))

        var payload: [UInt8] = []
        payload.reserveCapacity(44)
        payload.append(contentsOf: magicCode)
        payload.append(contentsOf: checkData)
        appendUInt32LE(checkCrc, to: &payload)
        return createCommand(type: .getTransmissionResumingAtBreakPoint, payload: payload)
    }

    /// Step 8: `0x80` fetchOTA (`0x10002a29c`, 12-byte payload)
    static func fetchOTA(imageData: Data) -> Data {
        let fullCrc = crc32(imageData)
        var payload: [UInt8] = []
        payload.reserveCapacity(12)
        payload.append(contentsOf: magicCode)
        appendUInt32LE(UInt32(imageData.count), to: &payload)
        appendUInt32LE(fullCrc, to: &payload)
        return createCommand(type: .fetchOTA, payload: payload)
    }

    /// Step 9: `0x86` config (`0x10002a460`, 92-byte payload)
    static func config(imageData: Data) -> Data? {
        guard imageData.count >= 4 else { return nil }
        let bytes = [UInt8](imageData)
        let n = bytes.count

        var payload: [UInt8] = []
        payload.reserveCapacity(92)
        appendUInt32LE(88, to: &payload) // Length prefix excluding trailing 4B CRC32
        payload.append(contentsOf: bytes[(n - 4)..<(n - 1)]) // 3 ASCII hex tail chars (e.g. "3CF")
        payload.append(0x00)
        payload.append(contentsOf: [UInt8](repeating: 0, count: 80))
        let configCrc = crc32(Data(payload))
        appendUInt32LE(configCrc, to: &payload)
        return createCommand(type: .config, payload: payload)
    }

    /// Step 10a: `0x85` data chunk
    static func dataPacket(chunk: Data) -> Data {
        createCommand(type: .data, payload: [UInt8](chunk))
    }

    /// Step 10b: `0x82` segmentCrcVerify (`0x10002a728`, 8-byte payload)
    static func segmentCrcVerify(segmentCrc: UInt32) -> Data {
        var payload: [UInt8] = []
        payload.reserveCapacity(8)
        payload.append(contentsOf: magicCode)
        appendUInt32LE(segmentCrc, to: &payload)
        return createCommand(type: .segmentCrcVerify, payload: payload)
    }

    /// Step 11: `0x88` imageCrcVerify (`0x100032998`, 0-byte payload)
    static func imageCrcVerify() -> Data {
        createCommand(type: .imageCrcVerify, payload: [])
    }

    /// Step 12: `0x92` imageOverwritingConfirmation (`0x10002a7f4`, "BEST")
    static func imageOverwritingConfirmation() -> Data {
        createCommand(type: .imageOverwritingConfirmation, payload: magicCode)
    }

    /// BES KFifo packet limit is `0x29d` (669) bytes including 5-byte TLV header -> 664-byte payload max
    static let maxDataChunkPayload = 664

    /// Split firmware image into 32 KB (`0x8000`) segments (`0x10003382c`)
    static func splitImageIntoSegments(imageData: Data, maxChunkPayload: Int) -> [ImageSegment] {
        let segmentSize = 32768 // 32 KB
        let clamped = min(maxChunkPayload, maxDataChunkPayload) & ~3
        let chunkSize = max(8, clamped)
        var segments: [ImageSegment] = []
        var offset = 0
        var idx = 0

        while offset < imageData.count {
            let end = min(offset + segmentSize, imageData.count)
            let segData = Data(imageData[offset..<end])
            let segCrc = crc32(segData)

            var chunks: [Data] = []
            var cOffset = segData.startIndex
            while cOffset < segData.endIndex {
                let cEnd = min(cOffset + chunkSize, segData.endIndex)
                chunks.append(Data(segData[cOffset..<cEnd]))
                cOffset = cEnd
            }

            segments.append(ImageSegment(index: idx, data: segData, crc32: segCrc, chunks: chunks))
            offset = end
            idx += 1
        }
        return segments
    }
}

enum OTACommandParser {
    /// Extract complete 5-byte TLV packets (`[type, lenLE(4B)] + payload`) from a buffered stream
    static func extractPackets(from buffer: inout Data) -> [(type: OTAPackageType, payload: Data)] {
        var packets: [(type: OTAPackageType, payload: Data)] = []
        while buffer.count >= 5 {
            let start = buffer.startIndex
            let opcode = buffer[start]
            let payloadLen = Int(
                UInt32(buffer[start + 1]) |
                (UInt32(buffer[start + 2]) << 8) |
                (UInt32(buffer[start + 3]) << 16) |
                (UInt32(buffer[start + 4]) << 24)
            )
            guard let type = OTAPackageType(rawValue: opcode),
                  payloadLen >= 0,
                  payloadLen <= 4096 else {
                // Drop leading out-of-sync byte and try next boundary
                buffer.removeFirst(1)
                continue
            }
            let totalLen = 5 + payloadLen
            guard buffer.count >= totalLen else {
                break
            }
            let payload = Data(buffer[(start + 5)..<(start + totalLen)])
            buffer.removeFirst(totalLen)
            packets.append((type, payload))
        }
        return packets
    }

    static func parsePacket(_ data: Data) -> (type: OTAPackageType, payload: Data)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 5,
              let type = OTAPackageType(rawValue: bytes[0]) else {
            return nil
        }
        let payloadLen = Int(
            UInt32(bytes[1]) |
            (UInt32(bytes[2]) << 8) |
            (UInt32(bytes[3]) << 16) |
            (UInt32(bytes[4]) << 24)
        )
        let available = bytes.count - 5
        let actualLen = min(max(0, payloadLen), available)
        let payload = Data(bytes[5..<(5 + actualLen)])
        return (type, payload)
    }

    /// `0x81` fetchOTA response: `"BEST..."` (optional LE UInt16 MTU at `[8..<10]`) or 1-byte `[0x01]`
    static func parseFetchOTAResponse(_ payload: Data) -> (accepted: Bool, negotiatedMtu: Int?) {
        let b = [UInt8](payload)
        if b.count >= 4 && Array(b[0..<4]) == OTACommand.magicCode {
            var mtu: Int? = nil
            if b.count >= 10 {
                let m = Int(UInt16(b[8]) | (UInt16(b[9]) << 8))
                if m > 0 {
                    mtu = m
                }
            }
            return (true, mtu)
        }
        if let first = b.first {
            return (first == 0x01, nil)
        }
        return (false, nil)
    }

    /// `0x10002a90c`
    static func parseDeviceInfo(_ payload: Data) -> OTADeviceInfo? {
        let b = [UInt8](payload)
        guard b.count >= 13,
              Array(b[0..<4]) == OTACommand.magicCode else {
            return nil
        }
        return OTADeviceInfo(
            deviceType: b[4],
            leftOrStereoVersion: Data(b[5..<9]),
            rightVersion: Data(b[9..<13])
        )
    }

    /// `0x10002ae30` & `0x10002ba3c`
    static func parseResumePacket(_ payload: Data) -> ResumePacket? {
        let b = [UInt8](payload)
        guard b.count >= 40 else { return nil }
        let breakpoint = UInt32(b[0]) |
            (UInt32(b[1]) << 8) |
            (UInt32(b[2]) << 16) |
            (UInt32(b[3]) << 24)
        let randomCode = Data(b[4..<36])
        let crc = UInt32(b[36]) |
            (UInt32(b[37]) << 8) |
            (UInt32(b[38]) << 16) |
            (UInt32(b[39]) << 24)
        var mtu: Int? = nil
        if b.count >= 42 {
            let m = Int(UInt16(b[40]) | (UInt16(b[41]) << 8))
            if m > 0 {
                mtu = m
            }
        }
        return ResumePacket(
            breakpoint: breakpoint,
            randomCode: randomCode,
            crc32: crc,
            negotiatedMtu: mtu
        )
    }
}
