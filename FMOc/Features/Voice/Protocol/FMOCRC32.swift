import Foundation

nonisolated enum FMOCRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { value in
        var crc = UInt32(value)
        for _ in 0 ..< 8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ UInt32.max
    }
}
