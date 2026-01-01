/// A variation axis value to apply to a variable font.
///
/// Use this to specify custom axis values when creating a `Font` instance.
///
/// ```swift
/// let font = try Font(family: "Inter", variations: [
///     .weight(600),
///     .width(90)
/// ])
/// ```
public struct FontVariation: Sendable, Hashable {
    /// The 4-character OpenType axis tag (e.g., "wght", "wdth").
    public let tag: String

    /// The axis value in design space coordinates.
    public let value: Double

    /// Creates a variation with a custom axis tag and value.
    public init(tag: String, value: Double) {
        self.tag = tag
        self.value = value
    }

    // MARK: - Registered Axis Tags

    /// Weight axis tag ("wght").
    public static let weightTag = "wght"

    /// Width axis tag ("wdth").
    public static let widthTag = "wdth"

    /// Slant axis tag ("slnt").
    public static let slantTag = "slnt"

    /// Italic axis tag ("ital").
    public static let italicTag = "ital"

    /// Optical size axis tag ("opsz").
    public static let opticalSizeTag = "opsz"

    /// Y-axis variation tag ("YAXS"). Used by Apple fonts for vertical metrics.
    public static let yAxisTag = "YAXS"

    // MARK: - Common Axes

    /// Weight axis (wght). Common range: 100–900.
    public static func weight(_ value: Double) -> FontVariation {
        FontVariation(tag: weightTag, value: value)
    }

    /// Width axis (wdth). Common range: 50–200, where 100 is normal.
    public static func width(_ value: Double) -> FontVariation {
        FontVariation(tag: widthTag, value: value)
    }

    /// Slant axis (slnt). Typically in degrees, negative for rightward slant.
    public static func slant(_ value: Double) -> FontVariation {
        FontVariation(tag: slantTag, value: value)
    }

    /// Italic axis (ital). Typically 0 (roman) or 1 (italic).
    public static func italic(_ value: Double) -> FontVariation {
        FontVariation(tag: italicTag, value: value)
    }

    /// Optical size axis (opsz). Typically matches the point size.
    public static func opticalSize(_ value: Double) -> FontVariation {
        FontVariation(tag: opticalSizeTag, value: value)
    }

    /// Y-axis variation (YAXS). Used by Apple fonts for vertical metrics adjustment.
    public static func yAxis(_ value: Double) -> FontVariation {
        FontVariation(tag: yAxisTag, value: value)
    }
}
