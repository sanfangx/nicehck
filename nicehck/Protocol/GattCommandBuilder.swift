import Foundation

struct GattCommandFrame {
    let command: UInt16
    let status: UInt8
    let payload: Data
    let crcValid: Bool
}

enum GattCommandBuilder {
    static let frameHeader: UInt8 = 0x4E // 'N'

    /// Exact implementation of `GattCommandBuilder.build` (`0x1000a503c`)
    /// Live runtime callers pass `includeCrc: false` (`w3 = 0`).
    static func build(
        command: UInt16,
        payload: [UInt8] = [],
        includeCrc: Bool = false
    ) -> Data {
        let length = UInt16(3 + payload.count)
        let crcFlag: UInt8 = includeCrc ? 0x01 : 0x00

        var bytes: [UInt8] = []
        bytes.reserveCapacity(6 + payload.count + (includeCrc ? 2 : 0))
        bytes.append(frameHeader)
        bytes.append(UInt8(length & 0xFF))
        bytes.append(UInt8((length >> 8) & 0xFF))
        bytes.append(crcFlag)
        bytes.append(UInt8(command & 0xFF))
        bytes.append(UInt8((command >> 8) & 0xFF))
        bytes.append(contentsOf: payload)

        if includeCrc {
            let crc = crc16Modbus(bytes)
            bytes.append(UInt8(crc & 0xFF))
            bytes.append(UInt8((crc >> 8) & 0xFF))
        }
        return Data(bytes)
    }

    /// Exact CRC-16/MODBUS (`0x1000a583c .. 0x1000a595c`)
    static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if (crc & 0x0001) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }
}
