import Foundation

/// A cross-platform utility for locating and loading font data by family name and style.
///
/// `FontRepository` looks up fonts by name and retrieves their raw data, supporting macOS
/// (CoreText), Windows (WinSDK), and Linux (Fontconfig).
///
public struct FontRepository: Sendable {
    /// Attempts to find a font that matches the given family name and optional style.
    ///
    /// This method uses platform-specific font APIs to locate a font that best matches
    /// the provided parameters. If found, it returns the font data along with the
    /// resolved family and style names.
    ///
    /// - Parameters:
    ///   - name: The requested font family name (e.g., "Arial").
    ///   - style: An optional style name (e.g., "Italic", "Bold"). Defaults to `nil`.
    /// - Returns: A `Match` struct containing the font data and resolved names, or `nil` if no match was found.
    /// - Throws: `LookupError.libraryInitializationFailed` if the platform font system failed to initialize,
    ///           `LookupError.readingFontFailed` if the font was found but could not be read,
    ///           or `LookupError.notSupported` if font lookup is not available on this platform.
    ///
    public static func matchForFont(family name: String, style: String? = nil) throws(LookupError) -> Match? {
#if canImport(CoreText)
        try matchForCoreTextFont(family: name, style: style)
#elseif canImport(WinSDK)
        try matchForWindowsFont(family: name, style: style)
#elseif canImport(Fontconfig)
        try matchForLinuxFont(family: name, style: style)
#else
        throw .notSupported
#endif
    }

    /// Whether font lookup is available on this platform.
    ///
    /// On Linux, this returns `true` only if Fontconfig support was compiled in.
    /// On macOS and Windows, this always returns `true`.
    public static var isAvailable: Bool {
#if canImport(CoreText) || canImport(WinSDK) || canImport(Fontconfig)
        true
#else
        false
#endif
    }

    /// Errors that can occur during font lookup.
    public enum LookupError: Error, Sendable {
        /// Indicates that the platform-specific font system could not be initialized.
        case libraryInitializationFailed

        /// Indicates that the font was found, but reading its data failed.
        case readingFontFailed

        /// Indicates that font lookup is not supported on this platform.
        /// On Linux, this occurs when Fontconfig support was not compiled in.
        case notSupported
    }

    /// A result structure representing a successfully matched font.
    ///
    /// Contains the raw font data and resolved family and style names.
    public struct Match: Sendable {
        /// The binary data of the matched font file.
        public let data: Data

        /// The resolved font family name (e.g., "Arial").
        public let familyName: String

        /// The resolved font style (e.g., "Bold Italic").
        public let style: String
    }
}
