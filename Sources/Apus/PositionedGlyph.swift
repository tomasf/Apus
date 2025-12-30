public struct PositionedGlyph: Sendable {
    /// The glyph's outline path (in font units, not yet positioned)
    public let path: Path

    /// The position where this glyph should be placed
    public let position: Point

    /// The glyph's advance (how far to move for the next glyph)
    public let advance: Point

    public init(path: Path, position: Point, advance: Point) {
        self.path = path
        self.position = position
        self.advance = advance
    }

    /// Returns the path translated to its final position
    public var positionedPath: Path {
        path.translated(by: position)
    }
}
