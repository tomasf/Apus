#if canImport(Fontconfig)
import Foundation
import Fontconfig

internal extension FontRepository {
    static func matchForLinuxFont(family name: String, style: String?) throws(LookupError) -> Match? {
        guard let config = FcInitLoadConfigAndFonts(),
              let pattern = FcPatternCreate()
        else {
            throw .libraryInitializationFailed
        }

        defer {
            FcPatternDestroy(pattern)
        }

        _ = name.withCString { FcPatternAddString(pattern, FC_FAMILY, $0) }
        if let style = style {
            _ = style.withCString { FcPatternAddString(pattern, FC_STYLE, $0) }
        }

        FcConfigSubstitute(config, pattern, FcMatchPattern)
        FcDefaultSubstitute(pattern)

        var result: FcResult = FcResultNoMatch
        guard let match = FcFontMatch(config, pattern, &result), result == FcResultMatch else {
            return nil
        }

        defer {
            FcPatternDestroy(match)
        }

        var matchFile, matchFamily, matchStyle: UnsafeMutablePointer<FcChar8>?
        guard FcPatternGetString(match, FC_FILE, 0, &matchFile) == FcResultMatch, let matchFile,
              FcPatternGetString(match, FC_FAMILY, 0, &matchFamily) == FcResultMatch, let matchFamily,
              FcPatternGetString(match, FC_STYLE, 0, &matchStyle) == FcResultMatch, let matchStyle
        else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: String(cString: matchFile)))
            return Match(data: data, familyName: String(cString: matchFamily), style: String(cString: matchStyle))
        } catch {
            throw .readingFontFailed
        }
    }
}

#endif
