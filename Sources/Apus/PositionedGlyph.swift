public struct PositionedGlyph: Sendable {
    /// The glyph's outline path (in font units, not yet positioned)
    public let path: Path

    /// The position where this glyph should be placed
    public let position: Point

    /// The glyph's advance (how far to move for the next glyph)
    public let advance: Point

    /// The cluster index identifying which part of the input text produced this glyph.
    ///
    /// Glyphs that originate from the same input character(s) share the same cluster value.
    /// This is useful for:
    /// - Applying tracking only between character clusters (not between base glyphs and combining marks)
    /// - Mapping glyph positions back to text positions for selection or cursor placement
    ///
    /// The value is a byte offset into the original UTF-8 string.
    public let cluster: UInt32

    public init(path: Path, position: Point, advance: Point, cluster: UInt32) {
        self.path = path
        self.position = position
        self.advance = advance
        self.cluster = cluster
    }

    /// Returns the path translated to its final position
    public var positionedPath: Path {
        path.translated(by: position)
    }
}
