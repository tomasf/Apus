internal import freetype
internal import harfbuzz
import Foundation

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

    public enum FontError: Error {
        case freetypeInitFailed
        case fontLoadFailed(String)
        case fontNotFound(family: String, style: String?)
        case faceNotFound(family: String, style: String?)
        case glyphLoadFailed(UInt32)
    }

    /// Whether system font lookup by family name is available on this platform.
    ///
    /// On macOS and Windows, this always returns `true`.
    /// On Linux, this returns `true` only if Fontconfig support was compiled in.
    public static var isSystemFontLookupAvailable: Bool {
        FontRepository.isAvailable
    }

    /// Load a font from a file path.
    public init(path: String, faceIndex: Int = 0) throws {
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
    public init(data: Data, faceIndex: Int = 0) throws {
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
    /// - Throws: `FontError.fontNotFound` if no matching font is found,
    ///           or `FontRepository.LookupError` if the lookup fails.
    public convenience init(family: String, style: String? = nil) throws {
        guard let match = try FontRepository.matchForFont(family: family, style: style) else {
            throw FontError.fontNotFound(family: family, style: style)
        }
        try self.init(data: match.data)
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
    /// - Throws: `FontError.faceNotFound` if no matching face is found.
    public convenience init(data: Data, family: String, style: String? = nil) throws {
        let faces = try Font.faces(in: data)
        guard let faceIndex = faces.firstIndex(where: { face in
            face.familyName == family && (style == nil || face.styleName == style)
        }) else {
            throw FontError.faceNotFound(family: family, style: style)
        }
        try self.init(data: data, faceIndex: faceIndex)
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

    /// Shape text and return positioned glyphs
    public func glyphs(for text: String) -> [PositionedGlyph] {
        // Create HarfBuzz buffer
        let buffer = hb_buffer_create()
        defer { hb_buffer_destroy(buffer) }

        // Add text to buffer
        text.withCString { cStr in
            hb_buffer_add_utf8(buffer, cStr, Int32(text.utf8.count), 0, Int32(text.utf8.count))
        }

        // Let HarfBuzz auto-detect direction, script, and language from text content
        hb_buffer_guess_segment_properties(buffer)

        // Shape!
        hb_shape(hbFont, buffer, nil, 0)

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
                result.append(PositionedGlyph(path: path, position: position, advance: advance))
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
}
