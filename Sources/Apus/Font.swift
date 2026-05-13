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
        try FontRepository.availableFamilies()
    }

    // MARK: - Initializers

    /// Designated initializer. The `loadFace` closure produces the FT_Face (typically via
    /// FT_New_Face or FT_New_Memory_Face) and throws a `FontError` on failure. `retainedData`
    /// is held for the lifetime of the font so memory-mapped face data stays valid.
    private init(
        retainedData: Data?,
        variations: [FontVariation],
        loadFace: (FT_Library) throws -> FT_Face
    ) throws {
        var library: FT_Library?
        guard FT_Init_FreeType(&library) == 0, let lib = library else {
            throw FontError.freetypeInitFailed
        }

        let face: FT_Face
        do {
            face = try loadFace(lib)
        } catch {
            FT_Done_FreeType(lib)
            throw error
        }

        self.ftLibrary = lib
        self.ftFace = face
        self.fontData = retainedData

        self.familyName = String(cString: face.pointee.family_name)
        self.styleName = String(cString: face.pointee.style_name)

        // A default char size is required for HarfBuzz; using a large size for better precision.
        // Actual visual scaling is done at render time.
        FT_Set_Char_Size(face, 0, FT_F26Dot6(1000 * 64), 72, 72)

        self.hbFont = hb_ft_font_create_referenced(face)
        Self.applyVariations(variations, hbFont: hbFont, ftFace: face, library: lib)

        let sizeMetrics = face.pointee.size.pointee.metrics
        self.metrics = FontMetrics(
            ascender: Double(fixed26_6: sizeMetrics.ascender),
            descender: Double(fixed26_6: sizeMetrics.descender),
            lineHeight: Double(fixed26_6: sizeMetrics.height),
            unitsPerEM: Double(face.pointee.units_per_EM)
        )
    }

    /// Load a font from a file path.
    ///
    /// - Parameters:
    ///   - path: Path to the font file.
    ///   - faceIndex: Index of the face within the font file (for .ttc collections).
    ///   - variations: Variation axis values to apply (for variable fonts).
    public convenience init(path: String, faceIndex: Int = 0, variations: [FontVariation] = []) throws {
        try self.init(retainedData: nil, variations: variations) { library in
            var face: FT_Face?
            guard FT_New_Face(library, path, FT_Long(faceIndex), &face) == 0, let face else {
                throw FontError.fontLoadFailed(path)
            }
            return face
        }
    }

    /// Load a font from binary data.
    ///
    /// - Parameters:
    ///   - data: The font file data.
    ///   - faceIndex: Index of the face within the font file (for .ttc collections).
    ///   - variations: Variation axis values to apply (for variable fonts).
    public convenience init(data: Data, faceIndex: Int = 0, variations: [FontVariation] = []) throws {
        try self.init(retainedData: data, variations: variations) { library in
            var face: FT_Face?
            let error = data.withUnsafeBytes { buffer in
                FT_New_Memory_Face(library, buffer.baseAddress?.assumingMemoryBound(to: FT_Byte.self), FT_Long(data.count), FT_Long(faceIndex), &face)
            }
            guard error == 0, let face else {
                throw FontError.fontLoadFailed("memory")
            }
            return face
        }
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
    ///           or an underlying error if the platform font system itself fails.
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
    private static func applyVariations(_ variations: [FontVariation], hbFont: OpaquePointer, ftFace: FT_Face, library: FT_Library) {
        guard !variations.isEmpty else { return }

        // Apply to HarfBuzz (for shaping/positioning)
        var hbVariations = variations.map { variation in
            hb_variation_t(tag: hb_tag_t(openTypeTag: variation.tag), value: Float(variation.value))
        }
        hb_font_set_variations(hbFont, &hbVariations, UInt32(hbVariations.count))

        // Apply to FreeType (for glyph outlines).
        // If the user passes duplicate entries for the same axis, the first one wins —
        // matching the previous behaviour.
        var mmVar: UnsafeMutablePointer<FT_MM_Var>?
        guard FT_Get_MM_Var(ftFace, &mmVar) == 0, let mm = mmVar else { return }
        defer { FT_Done_MM_Var(library, mm) }

        let valuesByTag = Dictionary(
            variations.map { (hb_tag_t(openTypeTag: $0.tag), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        var coords = (0..<Int(mm.pointee.num_axis)).map { i -> FT_Fixed in
            let axis = mm.pointee.axis[i]
            // FT_Var_Axis.tag is FT_ULong (UInt on 64-bit Unix); narrow to UInt32 for the lookup.
            if let value = valuesByTag[UInt32(axis.tag)] {
                return FT_Fixed(value * 65536.0)  // 16.16 fixed point
            }
            return axis.def
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
