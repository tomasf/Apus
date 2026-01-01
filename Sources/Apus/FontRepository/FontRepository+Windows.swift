#if canImport(WinSDK)
import Foundation
import WinSDK

internal extension FontRepository {
    static func matchForWindowsFont(family name: String, style: String?) throws(LookupError) -> Match? {
        guard let hdc = CreateCompatibleDC(nil) else {
            throw .libraryInitializationFailed
        }

        var logFont = LOGFONTW()
        let nameUTF16 = Array(name.utf16)
        _ = nameUTF16.withUnsafeBufferPointer { buffer in
            wcsncpy_s(&logFont.lfFaceName.0, Int(LF_FACESIZE), buffer.baseAddress, nameUTF16.count)
        }
        logFont.lfCharSet = BYTE(DEFAULT_CHARSET)

        class MatchContext {
            init(style: String?) {
                self.style = style
            }
            let style: String?
            var match: (LOGFONTW, family: String, style: String)?
        }

        let callback: FONTENUMPROCW = { lpelfe, _, _, lParam in
            let matcher = Unmanaged<MatchContext>.fromOpaque(UnsafeRawPointer(bitPattern: Int(lParam))!).takeUnretainedValue()
            guard var enumFont = UnsafePointer<ENUMLOGFONTEXW>(OpaquePointer(lpelfe))?.pointee else { return 1 }
            let fontStyle = withUnsafePointer(to: &enumFont.elfStyle) {
                $0.withMemoryRebound(to: UInt16.self, capacity: Int(LF_FACESIZE)) { ptr in
                    String(utf16CodeUnits: ptr, count: wcslen(ptr))
                }
            }
            let fontFamily = withUnsafePointer(to: &enumFont.elfLogFont.lfFaceName) {
                $0.withMemoryRebound(to: UInt16.self, capacity: Int(LF_FACESIZE)) { ptr in
                    String(utf16CodeUnits: ptr, count: wcslen(ptr))
                }
            }
            if fontStyle == (matcher.style ?? "Regular") {
                matcher.match = (enumFont.elfLogFont, fontFamily, fontStyle)
                return 0
            }
            return 1
        }

        let context = MatchContext(style: style)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        EnumFontFamiliesExW(hdc, &logFont, callback, LPARAM(Int(bitPattern: contextPointer)), 0)

        guard var (match, _, _) = context.match,
              let (_, matchFamily, matchStyle) = context.match,
              let hFont = CreateFontIndirectW(&match)
        else {
            DeleteDC(hdc)
            return nil
        }

        let oldFont = SelectObject(hdc, hFont)
        defer {
            if let oldFont {
                SelectObject(hdc, oldFont)
            }
            DeleteObject(hFont)
            DeleteDC(hdc)
        }

        let size = GetFontData(hdc, DWORD(0), 0, nil, 0)
        guard size != GDI_ERROR else {
            throw .readingFontFailed
        }

        var data = Data(count: Int(size))
        let success = data.withUnsafeMutableBytes { buffer in
            GetFontData(hdc, DWORD(0), 0, buffer.baseAddress, size) != GDI_ERROR
        }
        guard success else {
            throw LookupError.readingFontFailed
        }

        return Match(data: data, familyName: matchFamily, style: matchStyle)
    }

    static func availableWindowsFonts() throws(LookupError) -> [FontFamily] {
        guard let hdc = CreateCompatibleDC(nil) else {
            throw .libraryInitializationFailed
        }
        defer { DeleteDC(hdc) }

        class EnumContext {
            var families: [String: Set<String>] = [:]
        }

        let callback: FONTENUMPROCW = { lpelfe, _, _, lParam in
            let context = Unmanaged<EnumContext>.fromOpaque(UnsafeRawPointer(bitPattern: Int(lParam))!).takeUnretainedValue()
            guard var enumFont = UnsafePointer<ENUMLOGFONTEXW>(OpaquePointer(lpelfe))?.pointee else { return 1 }

            let fontFamily = withUnsafePointer(to: &enumFont.elfLogFont.lfFaceName) {
                $0.withMemoryRebound(to: UInt16.self, capacity: Int(LF_FACESIZE)) { ptr in
                    String(utf16CodeUnits: ptr, count: wcslen(ptr))
                }
            }
            let fontStyle = withUnsafePointer(to: &enumFont.elfStyle) {
                $0.withMemoryRebound(to: UInt16.self, capacity: Int(LF_FACESIZE)) { ptr in
                    String(utf16CodeUnits: ptr, count: wcslen(ptr))
                }
            }

            context.families[fontFamily, default: []].insert(fontStyle)
            return 1
        }

        var logFont = LOGFONTW()
        logFont.lfCharSet = BYTE(DEFAULT_CHARSET)

        let context = EnumContext()
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        EnumFontFamiliesExW(hdc, &logFont, callback, LPARAM(Int(bitPattern: contextPointer)), 0)

        return context.families.keys.sorted().map { family in
            FontFamily(name: family, styles: context.families[family]!.sorted())
        }
    }
}

#endif
