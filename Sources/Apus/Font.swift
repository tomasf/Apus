internal import freetype
internal import harfbuzz
import Foundation

/// Creates an OpenType tag from 4 ASCII characters (equivalent to HB_TAG macro)
internal func makeTag(_ c1: UInt8, _ c2: UInt8, _ c3: UInt8, _ c4: UInt8) -> hb_tag_t {
    (UInt32(c1) << 24) | (UInt32(c2) << 16) | (UInt32(c3) << 8) | UInt32(c4)
}

public final class Font: @unchecked Sendable {
    private let ftLibrary: FT_Library
    internal let ftFace: FT_Face
    internal let hbFont: OpaquePointer // hb_font_t*
    private let fontData: Data? // Retained for memory-based fonts

    /// The font's family name (e.g., "Helvetica").
    public let familyName: String

    /// The font's style name (e.g., "Bold", "Italic").
    public let styleName: String

    /// Font metrics for text layout.
    public let metrics: FontMetrics

    // MARK: - Errors

    public enum FontError: Error {
        case freetypeInitFailed
        case fontLoadFailed (String)
        case fontNotFound (family: String, style: String?)
        case faceNotFound (family: String, style: String?)
        case glyphLoadFailed (UInt32)
    }

    // MARK: - System Font Support

    /// Whether system font lookup by family name is available on this platform.
    ///
    /// On macOS and Windows, this always returns `true`.
    /// On Linux, this returns `true` only if Fontconfig support was compiled in.
    public static var isSystemFontLookupAvailable: Bool {
        FontRepository.isAvailable
    }

    /// A font family with its available styles.
    public struct Family: Sendable, Hashable {
        /// The font family name (e.g., "Arial").
        public let name: String

        /// The available styles for this family (e.g., ["Regular", "Bold", "Italic"]).
        public let styles: [String]
    }

    /// Returns all installed font families and their available styles.
    ///
    /// - Returns: An array of font families sorted by name, each containing its available styles.
    /// - Throws: If the platform font system fails to initialize or is not supported.
    public static func availableFamilies() throws -> [Family] {
        try FontRepository.availableFonts().map { Family(name: $0.name, styles: $0.styles) }
    }

    // MARK: - Initializers

    /// Load a font from a file path.
    ///
    /// - Parameters:
    ///   - path: Path to the font file.
    ///   - faceIndex: Index of the face within the font file (for .ttc collections).
    ///   - variations: Variation axis values to apply (for variable fonts).
    public init(path: String, faceIndex: Int = 0, variations: [FontVariation] = []) throws {
        // Initialize FreeType library
        var library: FT_Library?
        guard FT_Init_FreeType(&library) == 0, let lib = library else {
            throw FontError.freetypeInitFailed
        }

        // Load font face
        var face: FT_Face?
        let error = FT_New_Face(lib, path, FT_Long(faceIndex), &face)
        guard error == 0, let f = face else {
            FT_Done_FreeType(lib)
            throw FontError.fontLoadFailed(path)
        }
        self.ftLibrary = lib
        self.ftFace = f
        self.fontData = nil

        // Extract font names
        self.familyName = String(cString: f.pointee.family_name)
        self.styleName = String(cString: f.pointee.style_name)

        // Set a default size (required for HarfBuzz)
        // Using a large size for better precision; actual scaling is done later
        FT_Set_Char_Size(f, 0, FT_F26Dot6(1000 * 64), 72, 72)

        // Create HarfBuzz font from FreeType face
        self.hbFont = hb_ft_font_create_referenced(f)

        // Apply variation axis values if any
        Self.applyVariations(variations, to: hbFont, ftFace: f)

        // Extract font metrics
        let sizeMetrics = f.pointee.size.pointee.metrics
        let unitsPerEM = Double(f.pointee.units_per_EM)
        self.metrics = FontMetrics(
            ascender: Double(sizeMetrics.ascender) / 64.0,
            descender: Double(sizeMetrics.descender) / 64.0,
            lineHeight: Double(sizeMetrics.height) / 64.0,
            unitsPerEM: unitsPerEM
        )
    }

    /// Load a font from binary data.
    ///
    /// - Parameters:
    ///   - data: The font file data.
    ///   - faceIndex: Index of the face within the font file (for .ttc collections).
    ///   - variations: Variation axis values to apply (for variable fonts).
    public init(data: Data, faceIndex: Int = 0, variations: [FontVariation] = []) throws {
        // Initialize FreeType library
        var library: FT_Library?
        guard FT_Init_FreeType(&library) == 0, let lib = library else {
            throw FontError.freetypeInitFailed
        }

        // Load font face from memory
        var face: FT_Face?
        let error = data.withUnsafeBytes { buffer in
            FT_New_Memory_Face(lib, buffer.baseAddress?.assumingMemoryBound(to: FT_Byte.self), FT_Long(data.count), FT_Long(faceIndex), &face)
        }
        guard error == 0, let f = face else {
            FT_Done_FreeType(lib)
            throw FontError.fontLoadFailed("memory")
        }
        self.ftLibrary = lib
        self.ftFace = f
        self.fontData = data // Retain data to keep memory valid

        // Extract font names
        self.familyName = String(cString: f.pointee.family_name)
        self.styleName = String(cString: f.pointee.style_name)

        // Set a default size (required for HarfBuzz)
        FT_Set_Char_Size(f, 0, FT_F26Dot6(1000 * 64), 72, 72)

        // Create HarfBuzz font from FreeType face
        self.hbFont = hb_ft_font_create_referenced(f)

        // Apply variation axis values if any
        Self.applyVariations(variations, to: hbFont, ftFace: f)

        // Extract font metrics
        let sizeMetrics = f.pointee.size.pointee.metrics
        let unitsPerEM = Double(f.pointee.units_per_EM)
        self.metrics = FontMetrics(
            ascender: Double(sizeMetrics.ascender) / 64.0,
            descender: Double(sizeMetrics.descender) / 64.0,
            lineHeight: Double(sizeMetrics.height) / 64.0,
            unitsPerEM: unitsPerEM
        )
    }

    /// Load a font by family name and optional style using the system font repository.
    ///
    /// This uses platform-specific APIs to find fonts:
    /// - macOS/iOS: CoreText
    /// - Windows: GDI
    /// - Linux: Fontconfig (if enabled)
    ///
    /// - Parameters:
    ///   - family: The font family name (e.g., "Helvetica", "Arial").
    ///   - style: Optional style name (e.g., "Bold", "Italic"). Defaults to regular.
    ///   - variations: Variation axis values to apply (for variable fonts).
    /// - Throws: `FontError.fontNotFound` if no matching font is found,
    ///           or `FontRepository.LookupError` if the lookup fails.
    public convenience init(family: String, style: String? = nil, variations: [FontVariation] = []) throws {
        guard let match = try FontRepository.matchForFont(family: family, style: style) else {
            throw FontError.fontNotFound(family: family, style: style)
        }
        try self.init(data: match.data, variations: variations)
    }

    /// Load a font from binary data, matching by family name and optional style.
    ///
    /// This is useful for font collection files (.ttc) that contain multiple faces.
    /// The method searches through all faces in the font data to find a matching one.
    ///
    /// - Parameters:
    ///   - data: The font file data.
    ///   - family: The font family name to match.
    ///   - style: Optional style name to match. If nil, returns the first face matching the family.
    ///   - variations: Variation axis values to apply (for variable fonts).
    /// - Throws: `FontError.faceNotFound` if no matching face is found.
    public convenience init(data: Data, family: String, style: String? = nil, variations: [FontVariation] = []) throws {
        let faces = try Font.faces(in: data)
        guard let faceIndex = faces.firstIndex(where: { face in
            face.familyName == family && (style == nil || face.styleName == style)
        }) else {
            throw FontError.faceNotFound(family: family, style: style)
        }
        try self.init(data: data, faceIndex: faceIndex, variations: variations)
    }

    /// Load a font from a file path using a named instance.
    ///
    /// Named instances are predefined axis combinations like "Bold" or "Light Condensed".
    /// Use `namedInstances` to discover available instances.
    ///
    /// - Parameters:
    ///   - path: Path to the font file.
    ///   - faceIndex: Index of the face within the font file (for .ttc collections).
    ///   - namedInstance: Index of the named instance to use.
    public convenience init(path: String, faceIndex: Int = 0, namedInstance: Int) throws {
        try self.init(path: path, faceIndex: faceIndex)
        hb_font_set_var_named_instance(hbFont, UInt32(namedInstance))
    }

    /// Load a font from binary data using a named instance.
    ///
    /// Named instances are predefined axis combinations like "Bold" or "Light Condensed".
    /// Use `namedInstances` to discover available instances.
    ///
    /// - Parameters:
    ///   - data: The font file data.
    ///   - faceIndex: Index of the face within the font file (for .ttc collections).
    ///   - namedInstance: Index of the named instance to use.
    public convenience init(data: Data, faceIndex: Int = 0, namedInstance: Int) throws {
        try self.init(data: data, faceIndex: faceIndex)
        hb_font_set_var_named_instance(hbFont, UInt32(namedInstance))
    }

    deinit {
        hb_font_destroy(hbFont)
        FT_Done_Face(ftFace)
        FT_Done_FreeType(ftLibrary)
    }

    // MARK: - Internal Helpers

    /// Convert an OpenType tag to a 4-character string.
    internal func tagToString(_ tag: hb_tag_t) -> String {
        let bytes = [
            UInt8((tag >> 24) & 0xFF),
            UInt8((tag >> 16) & 0xFF),
            UInt8((tag >> 8) & 0xFF),
            UInt8(tag & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// Get a string from the font's name table.
    internal func getNameString(face: OpaquePointer!, nameID: hb_ot_name_id_t) -> String? {
        // Find an entry for this name ID to get its language
        var entryCount: UInt32 = 0
        guard let entries = hb_ot_name_list_names(face, &entryCount), entryCount > 0 else {
            return nil
        }

        // Find first entry matching this name ID
        var language: hb_language_t?
        for i in 0..<Int(entryCount) {
            if entries[i].name_id == nameID {
                language = entries[i].language
                break
            }
        }
        guard let language else { return nil }

        // Get the name string
        var length: UInt32 = 0
        _ = hb_ot_name_get_utf8(face, nameID, language, &length, nil)
        guard length > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(length) + 1)
        length = UInt32(buffer.count)
        _ = hb_ot_name_get_utf8(face, nameID, language, &length, &buffer)
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Apply variation axis values to HarfBuzz font and FreeType face.
    private static func applyVariations(_ variations: [FontVariation], to hbFont: OpaquePointer, ftFace: FT_Face) {
        guard !variations.isEmpty else { return }

        // Apply to HarfBuzz (for shaping/positioning)
        var hbVariations = variations.map { variation -> hb_variation_t in
            let bytes = Array(variation.tag.utf8.prefix(4))
            let tag = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
                      (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return hb_variation_t(tag: tag, value: Float(variation.value))
        }
        hb_font_set_variations(hbFont, &hbVariations, UInt32(hbVariations.count))

        // Apply to FreeType (for glyph outlines)
        // First get axis count and order from the font
        var ftMaster: UnsafeMutablePointer<FT_MM_Var>?
        guard FT_Get_MM_Var(ftFace, &ftMaster) == 0, let master = ftMaster else { return }
        defer { FT_Done_MM_Var(FT_Face(ftFace)?.pointee.glyph?.pointee.library, master) }

        // Build coordinate array in axis order
        var coords = [FT_Fixed](repeating: 0, count: Int(master.pointee.num_axis))
        for i in 0..<Int(master.pointee.num_axis) {
            let axis = master.pointee.axis[i]
            coords[i] = axis.def  // Start with default

            // Find if user specified this axis
            for variation in variations {
                let bytes = Array(variation.tag.utf8.prefix(4))
                let tag = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
                          (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
                if axis.tag == tag {
                    // Convert to 16.16 fixed point
                    coords[i] = FT_Fixed(variation.value * 65536.0)
                    break
                }
            }
        }
        FT_Set_Var_Design_Coordinates(ftFace, UInt32(coords.count), &coords)
    }
}
