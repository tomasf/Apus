internal import freetype
import Foundation

extension Font {
    // MARK: - Face Enumeration

    /// Describes a font face within a font file or collection.
    public struct Face: Sendable, Hashable {
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
    public static func faces(atPath path: String) throws -> [Face] {
        try enumerateFaces { library, index in
            var face: FT_Face?
            guard FT_New_Face(library, path, FT_Long(index), &face) == 0, let face else {
                throw Font.Error.fontLoadFailed(source: .path(path))
            }
            return face
        }
    }

    /// Returns information about all faces contained in font data.
    ///
    /// Font collection files (.ttc) can contain multiple faces. Use this method
    /// to enumerate them and find the appropriate face index.
    ///
    /// - Parameter data: The font file data.
    /// - Returns: Array of face information, one for each face in the file.
    public static func faces(in data: Data) throws -> [Face] {
        try enumerateFaces { library, index in
            var face: FT_Face?
            let error = data.withUnsafeBytes { buffer in
                FT_New_Memory_Face(library, buffer.baseAddress?.assumingMemoryBound(to: FT_Byte.self), FT_Long(data.count), FT_Long(index), &face)
            }
            guard error == 0, let face else {
                throw Font.Error.fontLoadFailed(source: .memory)
            }
            return face
        }
    }

    /// Shared implementation of `faces(atPath:)` and `faces(in:)`. The `loadFace` closure is
    /// called with face index -1 first (to read `num_faces` from any face), then once per face.
    private static func enumerateFaces(_ loadFace: (FT_Library, Int) throws -> FT_Face) throws -> [Face] {
        var library: FT_Library?
        guard FT_Init_FreeType(&library) == 0, let lib = library else {
            throw Font.Error.freetypeInitFailed
        }
        defer { FT_Done_FreeType(lib) }

        let probe = try loadFace(lib, -1)
        let faceCount = Int(probe.pointee.num_faces)
        FT_Done_Face(probe)

        var result: [Face] = []
        for index in 0..<faceCount {
            guard let face = try? loadFace(lib, index) else { continue }
            result.append(Face(
                index: index,
                familyName: String(cString: face.pointee.family_name),
                styleName: String(cString: face.pointee.style_name)
            ))
            FT_Done_Face(face)
        }
        return result
    }
}
