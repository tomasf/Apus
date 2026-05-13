internal import freetype
internal import harfbuzz
import Foundation

public final class Font: @unchecked Sendable {
    private let ftLibrary: FT_Library
    internal let ftFace: FT_Face
    internal let hbFont: OpaquePointer // hb_font_t*
    private let fontData: Data? // Retained for memory-based fonts

    /// The font's family name (e.g., "Helvetica").
    public let familyName: String

    /// The font's style name (e.g., "Bold", "Italic").
    ///
    /// For variable fonts loaded via a named instance, this reflects the instance's
    /// subfamily name (e.g., "Bold") rather than the underlying face's default style.
    public internal(set) var styleName: String

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
        try FontRepository.availableFamilies().map { Family(name: $0.name, styles: $0.styles) }
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
        guard let match = try FontRepository.match(family: family, style: style) else {
            throw FontError.fontNotFound(family: family, style: style)
        }
        try self.init(data: match.data, family: match.familyName, style: match.style, variations: variations)
    }

    /// Load a font from binary data, matching by family name and optional style.
    ///
    /// The match is resolved in this order:
    ///   1. A discrete face whose family and style names match (e.g. a member of a `.ttc` collection).
    ///   2. A named instance of a variable font whose subfamily name matches the requested style.
    ///
    /// - Parameters:
    ///   - data: The font file data.
    ///   - family: The font family name to match.
    ///   - style: Optional style name to match. If nil, returns the first face matching the family.
    ///   - variations: Variation axis values to apply (for variable fonts). When non-empty,
    ///     these override any matching named instance's axis values.
    /// - Throws: `FontError.faceNotFound` if no matching face or named instance is found.
    public convenience init(data: Data, family: String, style: String? = nil, variations: [FontVariation] = []) throws {
        let faces = try Font.faces(in: data)

        // Exact face match (covers .ttc collections and other multi-face files).
        if let face = faces.first(where: { f in
            f.familyName == family && (style == nil || f.styleName == style)
        }) {
            try self.init(data: data, faceIndex: face.index, variations: variations)
            return
        }

        // Named instance match inside a family-matching face (covers variable fonts where
        // the style is exposed as a fvar named instance — e.g. "Jost" / "Bold").
        if let style {
            for face in faces where face.familyName == family {
                if let instanceIndex = Self.findNamedInstance(in: data, faceIndex: face.index, named: style) {
                    try self.init(data: data, faceIndex: face.index, variations: variations)
                    if variations.isEmpty {
                        Self.applyNamedInstance(instanceIndex, hbFont: hbFont, ftFace: ftFace, library: ftLibrary)
                        self.styleName = style
                    }
                    return
                }
            }
        }

        throw FontError.faceNotFound(family: family, style: style)
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
        Self.applyNamedInstance(namedInstance, hbFont: hbFont, ftFace: ftFace, library: ftLibrary)
        if let name = Self.namedInstanceName(at: namedInstance, hbFont: hbFont) {
            self.styleName = name
        }
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
        Self.applyNamedInstance(namedInstance, hbFont: hbFont, ftFace: ftFace, library: ftLibrary)
        if let name = Self.namedInstanceName(at: namedInstance, hbFont: hbFont) {
            self.styleName = name
        }
    }

    deinit {
        hb_font_destroy(hbFont)
        FT_Done_Face(ftFace)
        FT_Done_FreeType(ftLibrary)
    }

    // MARK: - Internal Helpers

    /// Returns a string from the font's OpenType `name` table.
    internal static func nameString(face: OpaquePointer!, nameID: hb_ot_name_id_t) -> String? {
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

        // Probe full length (return value), then read into a sized buffer.
        // With a nil buffer, hb_ot_name_get_utf8 reports the length only via its return value;
        // the length out-param is not updated.
        var size: UInt32 = 0
        let fullLength = hb_ot_name_get_utf8(face, nameID, language, &size, nil)
        guard fullLength > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(fullLength) + 1)
        size = UInt32(buffer.count)
        _ = buffer.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: ptr.count) { cptr in
                hb_ot_name_get_utf8(face, nameID, language, &size, cptr)
            }
        }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    /// Applies variation axis values to the HarfBuzz font and FreeType face.
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

    /// Applies a named instance to both HarfBuzz (for shaping) and FreeType (for glyph outlines).
    /// `index` is the HarfBuzz-style 0-based instance index used by `NamedInstance.index`.
    internal static func applyNamedInstance(_ index: Int, hbFont: OpaquePointer, ftFace: FT_Face, library: FT_Library) {
        hb_font_set_var_named_instance(hbFont, UInt32(index))

        var mmVar: UnsafeMutablePointer<FT_MM_Var>?
        guard FT_Get_MM_Var(ftFace, &mmVar) == 0, let mm = mmVar else { return }
        defer { FT_Done_MM_Var(library, mm) }

        guard index >= 0, index < Int(mm.pointee.num_namedstyles) else { return }
        let namedStyle = mm.pointee.namedstyle[index]
        let numAxes = Int(mm.pointee.num_axis)
        var coords = Array(UnsafeBufferPointer(start: namedStyle.coords, count: numAxes))
        FT_Set_Var_Design_Coordinates(ftFace, UInt32(numAxes), &coords)
    }

    /// Returns the subfamily name for a named instance, looked up via the OpenType name table.
    internal static func namedInstanceName(at index: Int, hbFont: OpaquePointer) -> String? {
        let face = hb_font_get_face(hbFont)
        let count = hb_ot_var_get_named_instance_count(face)
        guard index >= 0, UInt32(index) < count else { return nil }
        let nameID = hb_ot_var_named_instance_get_subfamily_name_id(face, UInt32(index))
        return nameString(face: face, nameID: nameID)
    }

    /// Returns the HarfBuzz-style 0-based index of a named instance in the given font data
    /// whose subfamily name matches `styleName`, or `nil` if no instance matches.
    internal static func findNamedInstance(in data: Data, faceIndex: Int, named styleName: String) -> Int? {
        data.withUnsafeBytes { buffer -> Int? in
            guard let base = buffer.baseAddress else { return nil }
            let blob = hb_blob_create(
                base.assumingMemoryBound(to: CChar.self),
                UInt32(data.count),
                HB_MEMORY_MODE_READONLY,
                nil,
                nil
            )
            defer { hb_blob_destroy(blob) }

            let face = hb_face_create(blob, UInt32(faceIndex))
            defer { hb_face_destroy(face) }

            let count = hb_ot_var_get_named_instance_count(face)
            for i in 0..<count {
                let nameID = hb_ot_var_named_instance_get_subfamily_name_id(face, i)
                if let name = nameString(face: face, nameID: nameID), name == styleName {
                    return Int(i)
                }
            }
            return nil
        }
    }
}
