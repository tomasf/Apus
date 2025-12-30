import freetype
import harfbuzz
import Foundation

public final class Font: @unchecked Sendable {
    private let ftLibrary: FT_Library
    private let ftFace: FT_Face
    private let hbFont: OpaquePointer // hb_font_t*
    private let unitsPerEM: Double
    private let fontData: Data? // Retained for memory-based fonts

    public enum FontError: Error {
        case freetypeInitFailed
        case fontLoadFailed(String)
        case fontNotFound(family: String, style: String?)
        case glyphLoadFailed(UInt32)
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

        // Set a default size (required for HarfBuzz)
        // Using a large size for better precision; actual scaling is done later
        FT_Set_Char_Size(f, 0, FT_F26Dot6(1000 * 64), 72, 72)

        // Create HarfBuzz font from FreeType face
        self.hbFont = hb_ft_font_create_referenced(f)

        // Store units per EM for scaling
        self.unitsPerEM = Double(f.pointee.units_per_EM)
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

        // Set a default size (required for HarfBuzz)
        FT_Set_Char_Size(f, 0, FT_F26Dot6(1000 * 64), 72, 72)

        // Create HarfBuzz font from FreeType face
        self.hbFont = hb_ft_font_create_referenced(f)

        // Store units per EM for scaling
        self.unitsPerEM = Double(f.pointee.units_per_EM)
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

        // Set buffer properties
        hb_buffer_set_direction(buffer, HB_DIRECTION_LTR)
        hb_buffer_set_script(buffer, HB_SCRIPT_COMMON)
        hb_buffer_set_language(buffer, hb_language_get_default())

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
