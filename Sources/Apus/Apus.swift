import freetype
import harfbuzz

public struct Apus {

    /// Returns HarfBuzz version string
    public static func harfbuzzVersion() -> String {
        String(cString: hb_version_string())
    }

    /// Returns FreeType version as a tuple (compile-time version)
    public static func freetypeVersion() -> (major: Int, minor: Int, patch: Int) {
        (Int(FREETYPE_MAJOR), Int(FREETYPE_MINOR), Int(FREETYPE_PATCH))
    }

    /// Simple test to verify both libraries are linked
    public static func verify() -> Bool {
        // Test HarfBuzz
        let hbVersion = harfbuzzVersion()
        guard !hbVersion.isEmpty else { return false }

        // Test FreeType by checking version constants are defined
        let ftMajor = FREETYPE_MAJOR
        guard ftMajor > 0 else { return false }

        return true
    }
}
