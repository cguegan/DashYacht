/// NMEA 0183 sentence checksum.
///
/// The checksum is the XOR of all characters between the start character (`$` or `!`)
/// and `*`, written as two hexadecimal digits after `*`.
public enum Checksum {
    /// Returns `true` only when the sentence has a checksum and it matches the content.
    ///
    /// A sentence without a checksum is rejected: we cannot tell if it was corrupted on the wire.
    public static func isValid(_ sentence: some StringProtocol) -> Bool {
        let bytes = Array(sentence.utf8).trimmingTrailingLineEnd()
        guard let start = bytes.first, start == UInt8(ascii: "$") || start == UInt8(ascii: "!"),
              bytes.count >= 4, bytes[bytes.count - 3] == UInt8(ascii: "*"),
              let expected = UInt8(String(decoding: bytes.suffix(2), as: UTF8.self), radix: 16)
        else { return false }

        let computed = bytes[1..<(bytes.count - 3)].reduce(0, ^)
        return computed == expected
    }
}

private extension Array where Element == UInt8 {
    func trimmingTrailingLineEnd() -> [UInt8] {
        var result = self
        while let last = result.last, last == UInt8(ascii: "\r") || last == UInt8(ascii: "\n") {
            result.removeLast()
        }
        return result
    }
}
