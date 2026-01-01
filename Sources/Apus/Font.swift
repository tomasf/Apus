internal import freetype
internal import harfbuzz
import Foundation

/// Creates an OpenType tag from 4 ASCII characters (equivalent to HB_TAG macro)
private func makeTag(_ c1: UInt8, _ c2: UInt8, _ c3: UInt8, _ c4: UInt8) -> hb_tag_t {
    (UInt32(c1) << 24) | (UInt32(c2) << 16) | (UInt32(c3) << 8) | UInt32(c4)
}

public final class Font: @unchecked Sendable {
    private let ftLibrary: FT_Library
    private let ftFace: FT_Face
    private let hbFont: OpaquePointer // hb_font_t*
    private let fontData: Data? // Retained for memory-based fonts

    /// The font's family name (e.g., "Helvetica").
    public let familyName: String

    /// The font's style name (e.g., "Bold", "Italic").
    public let styleName: String

    /// Font metrics for text layout.
    public let metrics: FontMetrics

    // MARK: - Variable Font Support

    /// Whether this font is a variable font with variation axes.
    public var isVariable: Bool {
        let face = hb_font_get_face(hbFont)
        return hb_ot_var_has_data(face) != 0
    }

    /// The variation axes available in this font.
    ///
    /// Returns an empty array for non-variable fonts.
    public var variationAxes: [VariationAxis] {
        let face = hb_font_get_face(hbFont)

        var axisCount: UInt32 = 0
        let total = hb_ot_var_get_axis_infos(face, 0, &axisCount, nil)
        guard total > 0 else { return [] }

        var axisInfos = [hb_ot_var_axis_info_t](repeating: hb_ot_var_axis_info_t(), count: Int(total))
        axisCount = total
        _ = hb_ot_var_get_axis_infos(face, 0, &axisCount, &axisInfos)

        return axisInfos.prefix(Int(axisCount)).map { info in
            let tag = tagToString(info.tag)
            let name = getNameString(face: face, nameID: info.name_id) ?? Self.registeredAxisName(for: tag)
            return VariationAxis(
                tag: tag,
                name: name ?? tag,
                minValue: Double(info.min_value),
                defaultValue: Double(info.default_value),
                maxValue: Double(info.max_value)
            )
        }
    }

    /// Well-known names for variation axes.
    private static func registeredAxisName(for tag: String) -> String? {
        switch tag {
        case FontVariation.weightTag: return "Weight"
        case FontVariation.widthTag: return "Width"
        case FontVariation.slantTag: return "Slant"
        case FontVariation.italicTag: return "Italic"
        case FontVariation.opticalSizeTag: return "Optical Size"
        case FontVariation.yAxisTag: return "Y Axis"
        default: return nil
        }
    }

    /// The named instances (predefined axis combinations) available in this font.
    ///
    /// Named instances represent common variations like "Bold" or "Light Condensed".
    /// Returns an empty array for non-variable fonts.
    public var namedInstances: [NamedInstance] {
        let face = hb_font_get_face(hbFont)
        let count = hb_ot_var_get_named_instance_count(face)
        guard count > 0 else { return [] }

        let axisCount = hb_ot_var_get_axis_count(face)

        return (0..<count).compactMap { index in
            let nameID = hb_ot_var_named_instance_get_subfamily_name_id(face, index)
            let name = getNameString(face: face, nameID: nameID)

            var coordCount = axisCount
            var coords = [Float](repeating: 0, count: Int(axisCount))
            _ = hb_ot_var_named_instance_get_design_coords(face, index, &coordCount, &coords)

            return NamedInstance(
                index: Int(index),
                name: name ?? "Instance \(index)",
                coordinates: coords.prefix(Int(coordCount)).map { Double($0) }
            )
        }
    }

    /// Convert an OpenType tag to a 4-character string.
    private func tagToString(_ tag: hb_tag_t) -> String {
        let bytes = [
            UInt8((tag >> 24) & 0xFF),
            UInt8((tag >> 16) & 0xFF),
            UInt8((tag >> 8) & 0xFF),
            UInt8(tag & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// Get a string from the font's name table.
    private func getNameString(face: OpaquePointer!, nameID: hb_ot_name_id_t) -> String? {
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

    public enum FontError: Error {
        case freetypeInitFailed
        case fontLoadFailed (String)
        case fontNotFound (family: String, style: String?)
        case faceNotFound (family: String, style: String?)
        case glyphLoadFailed (UInt32)
    }

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

    /// Information about a font face within a font file or collection.
    public struct FaceInfo: Sendable, Hashable {
        /// The face index within the font file.
        public let index: Int

        /// The font family name.
        public let familyName: String

        /// The font style name.
        public let styleName: String
    }

    /// Returns information about all faces contained in a font file.
    ///
    /// Font collection files (.ttc) can contain multiple faces. Use this method
    /// to enumerate them and find the appropriate face index.
    ///
    /// - Parameter path: Path to the font file.
    /// - Returns: Array of face information, one for each face in the file.
    public static func faces(atPath path: String) throws -> [FaceInfo] {
        var library: FT_Library?
        guard FT_Init_FreeType(&library) == 0, let lib = library else {
            throw FontError.freetypeInitFailed
        }
        defer { FT_Done_FreeType(lib) }

        // Load with index -1 to get face count
        var face: FT_Face?
        guard FT_New_Face(lib, path, -1, &face) == 0, let f = face else {
            throw FontError.fontLoadFailed(path)
        }
        let faceCount = Int(f.pointee.num_faces)
        FT_Done_Face(f)

        var result: [FaceInfo] = []
        for i in 0..<faceCount {
            guard FT_New_Face(lib, path, FT_Long(i), &face) == 0, let f = face else {
                continue
            }
            result.append(FaceInfo(
                index: i,
                familyName: String(cString: f.pointee.family_name),
                styleName: String(cString: f.pointee.style_name)
            ))
            FT_Done_Face(f)
        }
        return result
    }

    /// Returns information about all faces contained in font data.
    ///
    /// Font collection files (.ttc) can contain multiple faces. Use this method
    /// to enumerate them and find the appropriate face index.
    ///
    /// - Parameter data: The font file data.
    /// - Returns: Array of face information, one for each face in the file.
    public static func faces(in data: Data) throws -> [FaceInfo] {
        var library: FT_Library?
        guard FT_Init_FreeType(&library) == 0, let lib = library else {
            throw FontError.freetypeInitFailed
        }
        defer { FT_Done_FreeType(lib) }

        // Load with index -1 to get face count
        var face: FT_Face?
        let loadResult = data.withUnsafeBytes { buffer in
            FT_New_Memory_Face(lib, buffer.baseAddress?.assumingMemoryBound(to: FT_Byte.self), FT_Long(data.count), -1, &face)
        }
        guard loadResult == 0, let f = face else {
            throw FontError.fontLoadFailed("memory")
        }
        let faceCount = Int(f.pointee.num_faces)
        FT_Done_Face(f)

        var result: [FaceInfo] = []
        for i in 0..<faceCount {
            let loadResult = data.withUnsafeBytes { buffer in
                FT_New_Memory_Face(lib, buffer.baseAddress?.assumingMemoryBound(to: FT_Byte.self), FT_Long(data.count), FT_Long(i), &face)
            }
            guard loadResult == 0, let f = face else {
                continue
            }
            result.append(FaceInfo(
                index: i,
                familyName: String(cString: f.pointee.family_name),
                styleName: String(cString: f.pointee.style_name)
            ))
            FT_Done_Face(f)
        }
        return result
    }

    deinit {
        hb_font_destroy(hbFont)
        FT_Done_Face(ftFace)
        FT_Done_FreeType(ftLibrary)
    }

    /// Shape text and return positioned glyphs.
    ///
    /// - Parameters:
    ///   - text: The text string to shape.
    ///   - features: Optional OpenType features to enable or disable during shaping.
    /// - Returns: An array of positioned glyphs with their paths and positions.
    ///
    /// Example:
    /// ```swift
    /// // Shape with small caps and old-style numerals
    /// let glyphs = font.glyphs(for: "Hello 123", features: [.smallCaps, .oldStyleNumerals])
    /// ```
    public func glyphs(for text: String, features: [OpenTypeFeature] = []) -> [PositionedGlyph] {
        // Create HarfBuzz buffer
        let buffer = hb_buffer_create()
        defer { hb_buffer_destroy(buffer) }

        // Add text to buffer
        text.withCString { cStr in
            hb_buffer_add_utf8(buffer, cStr, Int32(text.utf8.count), 0, Int32(text.utf8.count))
        }

        // Let HarfBuzz auto-detect direction, script, and language from text content
        hb_buffer_guess_segment_properties(buffer)

        // Convert OpenType features to HarfBuzz format and shape
        if features.isEmpty {
            hb_shape(hbFont, buffer, nil, 0)
        } else {
            var hbFeatures = features.map { feature -> hb_feature_t in
                let bytes = Array(feature.tag.utf8)
                let tag = makeTag(bytes[0], bytes[1], bytes[2], bytes[3])
                return hb_feature_t(
                    tag: tag,
                    value: feature.value,
                    start: 0,
                    end: UInt32.max // HB_FEATURE_GLOBAL_END
                )
            }
            hb_shape(hbFont, buffer, &hbFeatures, UInt32(hbFeatures.count))
        }

        // Get glyph info and positions
        var glyphCount: UInt32 = 0
        let glyphInfos = hb_buffer_get_glyph_infos(buffer, &glyphCount)
        let glyphPositions = hb_buffer_get_glyph_positions(buffer, &glyphCount)

        var result: [PositionedGlyph] = []
        var cursorX: Double = 0
        var cursorY: Double = 0

        for i in 0..<Int(glyphCount) {
            let info = glyphInfos![i]
            let pos = glyphPositions![i]

            let glyphID = info.codepoint
            let xOffset = Double(pos.x_offset) / 64.0
            let yOffset = Double(pos.y_offset) / 64.0
            let xAdvance = Double(pos.x_advance) / 64.0
            let yAdvance = Double(pos.y_advance) / 64.0

            let position = Point(x: cursorX + xOffset, y: cursorY + yOffset)
            let advance = Point(x: xAdvance, y: yAdvance)

            if let path = extractGlyphPath(glyphID: glyphID) {
                result.append(PositionedGlyph(path: path, position: position, advance: advance, cluster: info.cluster))
            }

            cursorX += xAdvance
            cursorY += yAdvance
        }

        return result
    }

    /// Extract the outline path for a specific glyph
    private func extractGlyphPath(glyphID: UInt32) -> Path? {
        // Load glyph
        let error = FT_Load_Glyph(ftFace, FT_UInt(glyphID), FT_Int32(FT_LOAD_NO_BITMAP))
        guard error == 0 else { return nil }

        let glyph = ftFace.pointee.glyph
        guard glyph?.pointee.format == FT_GLYPH_FORMAT_OUTLINE else { return nil }

        var outline = glyph!.pointee.outline
        var path = Path()

        // Define outline decomposition callbacks
        var funcs = FT_Outline_Funcs(
            move_to: { (to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                // Close previous contour if there is one
                if !path.pointee.isEmpty {
                    path.pointee.close()
                }
                let point = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.moveTo(point)
                return 0
            },
            line_to: { (to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                let point = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.lineTo(point)
                return 0
            },
            conic_to: { (control, to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                let ctrl = Point(
                    x: Double(control!.pointee.x) / 64.0,
                    y: Double(control!.pointee.y) / 64.0
                )
                let end = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.quadraticTo(control: ctrl, end: end)
                return 0
            },
            cubic_to: { (control1, control2, to, user) -> Int32 in
                let path = user!.assumingMemoryBound(to: Path.self)
                let c1 = Point(
                    x: Double(control1!.pointee.x) / 64.0,
                    y: Double(control1!.pointee.y) / 64.0
                )
                let c2 = Point(
                    x: Double(control2!.pointee.x) / 64.0,
                    y: Double(control2!.pointee.y) / 64.0
                )
                let end = Point(
                    x: Double(to!.pointee.x) / 64.0,
                    y: Double(to!.pointee.y) / 64.0
                )
                path.pointee.cubicTo(control1: c1, control2: c2, end: end)
                return 0
            },
            shift: 0,
            delta: 0
        )

        withUnsafeMutablePointer(to: &path) { pathPtr in
            _ = FT_Outline_Decompose(&outline, &funcs, pathPtr)
        }

        // Close path if needed (FreeType doesn't always emit close)
        if !path.isEmpty {
            path.close()
        }

        return path
    }

    // MARK: - OpenType Feature Enumeration

    /// Returns the OpenType features available in this font.
    ///
    /// This includes features from both the GSUB (substitution) and GPOS (positioning) tables.
    /// Common features include ligatures, small caps, numerals styles, and kerning.
    ///
    /// - Returns: An array of 4-character feature tag strings (e.g., "liga", "smcp", "kern").
    public var availableFeatures: [String] {
        let face = hb_font_get_face(hbFont)

        var allTags = Set<hb_tag_t>()

        // Get features from GSUB table (substitutions like ligatures, small caps)
        let gsubTag = makeTag(UInt8(ascii: "G"), UInt8(ascii: "S"), UInt8(ascii: "U"), UInt8(ascii: "B"))
        allTags.formUnion(getFeatureTags(face: face, tableTag: gsubTag))

        // Get features from GPOS table (positioning like kerning)
        let gposTag = makeTag(UInt8(ascii: "G"), UInt8(ascii: "P"), UInt8(ascii: "O"), UInt8(ascii: "S"))
        allTags.formUnion(getFeatureTags(face: face, tableTag: gposTag))

        // Convert tags to strings
        return allTags.map { tag in
            let bytes = [
                UInt8((tag >> 24) & 0xFF),
                UInt8((tag >> 16) & 0xFF),
                UInt8((tag >> 8) & 0xFF),
                UInt8(tag & 0xFF)
            ]
            return String(bytes: bytes, encoding: .ascii) ?? "????"
        }.sorted()
    }

    /// Get feature tags from a specific OpenType table
    private func getFeatureTags(face: OpaquePointer!, tableTag: hb_tag_t) -> [hb_tag_t] {
        // First call to get the count
        var count: UInt32 = 0
        let total = hb_ot_layout_table_get_feature_tags(face, tableTag, 0, &count, nil)

        guard total > 0 else { return [] }

        // Allocate buffer and get tags
        var tags = [hb_tag_t](repeating: 0, count: Int(total))
        count = total
        _ = hb_ot_layout_table_get_feature_tags(face, tableTag, 0, &count, &tags)

        return Array(tags.prefix(Int(count)))
    }
}
