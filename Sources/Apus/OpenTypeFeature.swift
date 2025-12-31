/// Represents an OpenType font feature that can be enabled or disabled during text shaping.
///
/// OpenType features control typographic behaviors like ligatures, small caps,
/// alternate numerals, and stylistic variations.
///
/// Example usage:
/// ```swift
/// let glyphs = font.glyphs(for: "Hello", features: [.smallCaps, .oldStyleNumerals])
/// ```
public struct OpenTypeFeature: Sendable, Hashable {
    /// The 4-character OpenType feature tag.
    public let tag: String

    /// The feature value. Typically 1 to enable, 0 to disable.
    /// Some features support other values for selecting alternates.
    public let value: UInt32

    /// Creates a feature with the specified tag and value.
    /// - Parameters:
    ///   - tag: The 4-character OpenType feature tag (e.g., "smcp", "liga").
    ///   - value: The feature value (default is 1 to enable).
    public init(tag: String, value: UInt32 = 1) {
        precondition(tag.count == 4, "OpenType feature tag must be exactly 4 characters")
        self.tag = tag
        self.value = value
    }

    /// Creates an enabled feature with the specified tag.
    public static func enabled(_ tag: String) -> OpenTypeFeature {
        OpenTypeFeature(tag: tag, value: 1)
    }

    /// Creates a disabled feature with the specified tag.
    public static func disabled(_ tag: String) -> OpenTypeFeature {
        OpenTypeFeature(tag: tag, value: 0)
    }
}

// MARK: - Common Features

extension OpenTypeFeature {
    // MARK: Ligatures

    /// Standard ligatures (liga). Enabled by default in most fonts.
    public static let standardLigatures = OpenTypeFeature(tag: "liga")

    /// Disable standard ligatures.
    public static let noStandardLigatures = OpenTypeFeature(tag: "liga", value: 0)

    /// Discretionary ligatures (dlig). Usually disabled by default.
    public static let discretionaryLigatures = OpenTypeFeature(tag: "dlig")

    /// Contextual alternates (calt). Enabled by default in most fonts.
    public static let contextualAlternates = OpenTypeFeature(tag: "calt")

    /// Disable contextual alternates.
    public static let noContextualAlternates = OpenTypeFeature(tag: "calt", value: 0)

    // MARK: Letter Case

    /// Small capitals (smcp). Converts lowercase to small caps.
    public static let smallCaps = OpenTypeFeature(tag: "smcp")

    /// All small capitals (c2sc + smcp). Converts all letters to small caps.
    public static let capsToSmallCaps = OpenTypeFeature(tag: "c2sc")

    /// Petite capitals (pcap).
    public static let petiteCaps = OpenTypeFeature(tag: "pcap")

    /// Unicase (unic). Mixed uppercase and lowercase forms.
    public static let unicase = OpenTypeFeature(tag: "unic")

    // MARK: Numerals

    /// Old-style numerals (onum). Varying heights, some descend below baseline.
    public static let oldStyleNumerals = OpenTypeFeature(tag: "onum")

    /// Lining numerals (lnum). Uniform height, aligned to cap height.
    public static let liningNumerals = OpenTypeFeature(tag: "lnum")

    /// Proportional numerals (pnum). Variable width.
    public static let proportionalNumerals = OpenTypeFeature(tag: "pnum")

    /// Tabular numerals (tnum). Fixed width for alignment in tables.
    public static let tabularNumerals = OpenTypeFeature(tag: "tnum")

    /// Slashed zero (zero). Distinguishes 0 from O.
    public static let slashedZero = OpenTypeFeature(tag: "zero")

    // MARK: Fractions

    /// Fractions (frac). Converts sequences like 1/2 to proper fractions.
    public static let fractions = OpenTypeFeature(tag: "frac")

    /// Ordinals (ordn). Superscript letters for ordinal indicators (1st, 2nd).
    public static let ordinals = OpenTypeFeature(tag: "ordn")

    // MARK: Position

    /// Superscript (sups).
    public static let superscript = OpenTypeFeature(tag: "sups")

    /// Subscript (subs).
    public static let `subscript` = OpenTypeFeature(tag: "subs")

    /// Scientific inferiors (sinf). For chemical formulas like H₂O.
    public static let scientificInferiors = OpenTypeFeature(tag: "sinf")

    // MARK: Stylistic

    /// Swash (swsh). Decorative letter variants.
    public static let swash = OpenTypeFeature(tag: "swsh")

    /// Historical forms (hist).
    public static let historicalForms = OpenTypeFeature(tag: "hist")

    /// Titling alternates (titl). Designed for large display sizes.
    public static let titling = OpenTypeFeature(tag: "titl")

    /// Stylistic set 1 (ss01).
    public static let stylisticSet1 = OpenTypeFeature(tag: "ss01")

    /// Stylistic set 2 (ss02).
    public static let stylisticSet2 = OpenTypeFeature(tag: "ss02")

    /// Stylistic set 3 (ss03).
    public static let stylisticSet3 = OpenTypeFeature(tag: "ss03")

    /// Stylistic set 4 (ss04).
    public static let stylisticSet4 = OpenTypeFeature(tag: "ss04")

    /// Stylistic set 5 (ss05).
    public static let stylisticSet5 = OpenTypeFeature(tag: "ss05")

    /// Stylistic set 6 (ss06).
    public static let stylisticSet6 = OpenTypeFeature(tag: "ss06")

    /// Stylistic set 7 (ss07).
    public static let stylisticSet7 = OpenTypeFeature(tag: "ss07")

    /// Stylistic set 8 (ss08).
    public static let stylisticSet8 = OpenTypeFeature(tag: "ss08")

    /// Stylistic set 9 (ss09).
    public static let stylisticSet9 = OpenTypeFeature(tag: "ss09")

    /// Stylistic set 10 (ss10).
    public static let stylisticSet10 = OpenTypeFeature(tag: "ss10")

    /// Returns a stylistic set feature by number (1-20).
    public static func stylisticSet(_ number: Int) -> OpenTypeFeature {
        precondition((1...20).contains(number), "Stylistic set number must be 1-20")
        return OpenTypeFeature(tag: String(format: "ss%02d", number))
    }

    /// Character variant (cv01-cv99).
    public static func characterVariant(_ number: Int) -> OpenTypeFeature {
        precondition((1...99).contains(number), "Character variant number must be 1-99")
        return OpenTypeFeature(tag: String(format: "cv%02d", number))
    }

    // MARK: Kerning

    /// Kerning (kern). Usually enabled by default.
    public static let kerning = OpenTypeFeature(tag: "kern")

    /// Disable kerning.
    public static let noKerning = OpenTypeFeature(tag: "kern", value: 0)
}
