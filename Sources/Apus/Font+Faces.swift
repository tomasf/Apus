internal import freetype
import Foundation

extension Font {
    // MARK: - Face Enumeration

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
}
