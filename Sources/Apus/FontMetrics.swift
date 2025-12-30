/// Font metrics for text layout.
///
/// All values are in font units scaled to the current size setting.
/// Use these values for calculating line heights, baseline positions, and text bounds.
public struct FontMetrics: Sendable, Hashable {
    /// Distance from the baseline to the top of the tallest glyph (positive value).
    public let ascender: Double

    /// Distance from the baseline to the bottom of the lowest descender (negative value).
    public let descender: Double

    /// Recommended line height (distance between baselines).
    public let lineHeight: Double

    /// The font's units per EM, useful for scaling calculations.
    public let unitsPerEM: Double

    public init(ascender: Double, descender: Double, lineHeight: Double, unitsPerEM: Double) {
        self.ascender = ascender
        self.descender = descender
        self.lineHeight = lineHeight
        self.unitsPerEM = unitsPerEM
    }

    /// The total height of a line from descender to ascender.
    public var lineExtent: Double {
        ascender - descender
    }
}
