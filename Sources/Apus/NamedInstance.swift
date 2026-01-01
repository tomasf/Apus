/// A predefined variation instance in a variable font.
///
/// Named instances are specific combinations of axis values that the font designer
/// has defined as useful presets (e.g., "Semibold Condensed", "Light Italic").
/// They correspond to what would traditionally be separate font files.
public struct NamedInstance: Sendable, Hashable {
    /// The instance index, for use with `Font.init(namedInstance:)`.
    public let index: Int

    /// The human-readable name of this instance (e.g., "Bold", "Light Condensed").
    public let name: String

    /// The design coordinates for this instance, one value per axis in axis order.
    public let coordinates: [Double]

    /// Creates a new named instance description.
    public init(index: Int, name: String, coordinates: [Double]) {
        self.index = index
        self.name = name
        self.coordinates = coordinates
    }
}
