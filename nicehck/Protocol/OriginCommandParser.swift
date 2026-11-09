import Foundation

enum OriginCommandParser {
    /// Stream frame splitter (`0x10004ad5c`)
    static func extractFrames(from buffer: inout Data) -> [Data] {
        var frames: [Data] = []

        while !buffer.isEmpty {
            if let headerIdx = buffer.firstIndex(of: GattCommandBuilder.frameHeader) {
                if headerIdx > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<headerIdx)
                }
            } else {
                buffer.removeAll()
                break
            }

            guard buffer.count >= 6 else { break }

            let b = [UInt8](buffer.prefix(6))
            let length = Int(UInt16(b[1]) | (UInt16(b[2]) << 8))
            let crcFlag = b[3]

            // Guard against corrupted length values
            if length < 3 || length > 512 {
                buffer.removeFirst()
                continue
            }

            let totalFrameLen = length + (crcFlag == 1 ? 5 : 3)
            guard buffer.count >= totalFrameLen else { break }

            let frame = Data(buffer.prefix(totalFrameLen))
            buffer.removeFirst(totalFrameLen)
            frames.append(frame)
        }

        return frames
    }

    /// Frame header & payload parser (`0x1000a6794`)
    static func parseFrame(_ frame: Data) -> GattCommandFrame? {
        let bytes = [UInt8](frame)
        guard bytes.count >= 6, bytes[0] == GattCommandBuilder.frameHeader else {
            return nil
        }

        let length = Int(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
        let crcFlag = bytes[3]
        let expectedLen = length + (crcFlag == 1 ? 5 : 3)
        guard bytes.count >= expectedLen else { return nil }

        let command = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)

        if crcFlag != 0 {
            guard expectedLen >= 9 else { return nil }
            let status = bytes[6]
            let payloadBytes = Array(bytes[7..<(expectedLen - 2)])
            let receivedCrc = UInt16(bytes[expectedLen - 2]) | (UInt16(bytes[expectedLen - 1]) << 8)
            let computedCrc = GattCommandBuilder.crc16Modbus(Array(bytes[0..<(expectedLen - 2)]))
            return GattCommandFrame(
                command: command,
                status: status,
                payload: Data(payloadBytes),
                crcValid: receivedCrc == computedCrc
            )
        } else {
            let payloadBytes = Array(bytes[6..<expectedLen])
            return GattCommandFrame(
                command: command,
                status: 0,
                payload: Data(payloadBytes),
                crcValid: true
            )
        }
    }

    /// `0x1000a6a0c`: Used for `0x0001` (`btDeviceId`) and `0x0003` (`firmwareVersion`)
    static func parseTwoByteUpperHex(_ payload: Data) -> String {
        let b = [UInt8](payload)
        guard b.count >= 2 else { return "?.?" }
        return String(format: "%02X%02X", b[0], b[1])
    }

    /// `0x1000a6b5c`: Used for `0x0004` (`serialNumber`)
    static func parseLowerHexString(_ payload: Data) -> String {
        payload.map { String(format: "%02x", $0) }.joined()
    }

    /// `0x1000a6d7c`: Used for `0x0005` (`batteryLevel`)
    static func parseBatteryLevel(_ payload: Data) -> BatteryLevel? {
        let b = [UInt8](payload)
        guard b.count >= 3 else { return nil }
        return BatteryLevel(
            left: Int(b[0]),
            right: Int(b[1]),
            box: Int(b[2])
        )
    }

    /// `0x1000a6e5c`: Used for `0x0101` (`noiseControl`)
    static func parseNoiseControl(_ payload: Data) -> NoiseControl? {
        guard let first = payload.first,
              let mode = NoiseMode.fromWireByte(first) else {
            return nil
        }
        return NoiseControl(mode: mode)
    }

    /// `0x1000a6f04`: Used for `0x0102` (`toneVolume`)
    static func parseToneVolume(_ payload: Data) -> Int? {
        guard let first = payload.first else { return nil }
        return Int(first)
    }

    /// `0x1000a6f0c`: Used for `0x0103` (`touchControl`)
    static func parseTouchControl(_ payload: Data) -> TouchControl? {
        let b = [UInt8](payload)
        guard b.count >= 4, b.count % 4 == 0 else { return nil }
        var items: [TouchControlItem] = []
        for idx in stride(from: 0, to: b.count, by: 4) {
            let sideByte = b[idx]
            let opByte = b[idx + 2]
            let funcByte = b[idx + 3]

            guard let side = TouchControlSide(rawValue: sideByte),
                  let operation = TouchControlOperation(rawValue: opByte) else {
                continue
            }
            let function = TouchControlFunc(rawValue: funcByte) ?? .none
            items.append(
                TouchControlItem(
                    side: side,
                    keyType: .noType,
                    operation: operation,
                    function: function
                )
            )
        }
        return TouchControl(items: items)
    }

    /// `0x1000a70c4`: Used for `0x0104` (`codec`)
    static func parseCodec(_ payload: Data) -> CodecEnum? {
        guard let first = payload.first else { return nil }
        return first == 0x01 ? .lhdc : .acc
    }

    /// `0x1000a7130`: Used for `0x0105`, `0x0106`, `0x0108`, `0x0109`, `0x01E1`
    static func parseBool(_ payload: Data) -> Bool? {
        guard let first = payload.first else { return nil }
        return first == 0x01
    }

    /// `0x1000a719c`: Used for `0x0107` (`eqIndex`)
    static func parseEqIndex(_ payload: Data) -> Int? {
        guard let first = payload.first else { return nil }
        return Int(first)
    }

    /// `0x1000a720c`: Used for `0x010A` (`ancTouchControl`)
    static func parseAncTouchControl(_ payload: Data) -> AncTouchControl? {
        let b = [UInt8](payload)
        guard b.count >= 2, b.count % 2 == 0 else { return nil }
        var items: [AncTouchControlItem] = []
        for idx in stride(from: 0, to: b.count, by: 2) {
            guard let fn = NoiseFunc(rawValue: b[idx]) else { continue }
            let isCheck = (b[idx + 1] == 0x01)
            items.append(AncTouchControlItem(function: fn, isCheck: isCheck))
        }
        return AncTouchControl(ancTouchControlItems: items)
    }
}
