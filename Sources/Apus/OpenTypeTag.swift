internal import harfbuzz

internal extension hb_tag_t {
    /// Builds an OpenType tag from a 4-character ASCII string (e.g. `"GSUB"`, `"wght"`).
    init(openTypeTag tag: String) {
        precondition(tag.utf8.count == 4, "OpenType tag must be exactly 4 ASCII bytes")
        let b = Array(tag.utf8)
        self = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    /// The 4-character ASCII representation of this OpenType tag.
    var openTypeTag: String {
        let bytes = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
