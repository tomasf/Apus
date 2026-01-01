/// Describes a variable font axis.
///
/// Variable fonts can have one or more design axes (such as weight, width, or slant)
/// that allow continuous variation between design extremes.
public struct VariationAxis: Sendable, Hashable {
    /// The 4-character OpenType axis tag (e.g., "wght", "wdth", "slnt").
    public let tag: String

    /// The human-readable name of the axis from the font's name table.
    public let name: String

    /// The minimum value on this axis.
    public let minValue: Double

    /// The default value on this axis.
    public let defaultValue: Double

    /// The maximum value on this axis.
    public let maxValue: Double

    /// Creates a new variation axis description.
    public init(tag: String, name: String, minValue: Double, defaultValue: Double, maxValue: Double) {
        self.tag = tag
        self.name = name
        self.minValue = minValue
        self.defaultValue = defaultValue
        self.maxValue = maxValue
    }
}
