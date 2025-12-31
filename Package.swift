// swift-tools-version: 6.2

import PackageDescription

// Platform-specific source files for FreeType
#if os(macOS) || os(iOS)
let ftSystem = "builds/unix/ftsystem.c"
let ftDebug = "src/base/ftdebug.c"
#elseif os(Windows)
let ftSystem = "builds/windows/ftsystem.c"
let ftDebug = "builds/windows/ftdebug.c"
#else
let ftSystem = "src/base/ftsystem.c"
let ftDebug = "src/base/ftdebug.c"
#endif

let package = Package(
    name: "Apus",
    products: [
        .library(name: "Apus", targets: ["Apus"]),
    ],
    traits: [
        .trait(name: "Fontconfig", description: "Enable Fontconfig support for font discovery on Linux"),
        .default(enabledTraits: ["Fontconfig"]),
    ],
    targets: [
        .target(
            name: "Apus",
            dependencies: [
                "harfbuzz",
                "freetype",
                .target(
                    name: "Fontconfig",
                    condition: .when(platforms: [.linux], traits: ["Fontconfig"])
                ),
            ]
        ),
        .testTarget(
            name: "ApusTests",
            dependencies: ["Apus"]
        ),
        .target(
            name: "freetype",
            path: "Sources/freetype",
            sources: [
                ftSystem,
                ftDebug,
                "src/autofit/autofit.c",
                "src/base/ftbase.c",
                "src/base/ftbbox.c",
                "src/base/ftbdf.c",
                "src/base/ftbitmap.c",
                "src/base/ftcid.c",
                "src/base/ftfstype.c",
                "src/base/ftgasp.c",
                "src/base/ftglyph.c",
                "src/base/ftgxval.c",
                "src/base/ftinit.c",
                "src/base/ftmm.c",
                "src/base/ftotval.c",
                "src/base/ftpatent.c",
                "src/base/ftpfr.c",
                "src/base/ftstroke.c",
                "src/base/ftsynth.c",
                "src/base/fttype1.c",
                "src/base/ftwinfnt.c",
                "src/bdf/bdf.c",
                "src/bzip2/ftbzip2.c",
                "src/cache/ftcache.c",
                "src/cff/cff.c",
                "src/cid/type1cid.c",
                "src/gzip/ftgzip.c",
                "src/lzw/ftlzw.c",
                "src/pcf/pcf.c",
                "src/pfr/pfr.c",
                "src/psaux/psaux.c",
                "src/pshinter/pshinter.c",
                "src/psnames/psnames.c",
                "src/raster/raster.c",
                "src/sdf/sdf.c",
                "src/sfnt/sfnt.c",
                "src/smooth/smooth.c",
                "src/svg/svg.c",
                "src/truetype/truetype.c",
                "src/type1/type1.c",
                "src/type42/type42.c",
                "src/winfonts/winfnt.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("FT2_BUILD_LIBRARY"),
                .define("FT_CONFIG_CONFIG_H", to: "<freetype/config/ftconfig.h>"),
                .define("FT_CONFIG_OPTIONS_H", to: "<freetype/config/ftoption.h>"),
                .define("HAVE_UNISTD_H", to: "1", .when(platforms: [.macOS, .iOS, .linux])),
                .define("HAVE_FCNTL_H", to: "1", .when(platforms: [.macOS, .iOS, .linux])),
            ]
        ),
        .target(
            name: "harfbuzz",
            dependencies: ["freetype"],
            path: "Sources/harfbuzz",
            sources: ["src/harfbuzz.cc"],
            publicHeadersPath: "src",
            cxxSettings: [
                .define("HAVE_FREETYPE"),
            ]
        ),
        .systemLibrary(
            name: "Fontconfig",
            path: "Sources/Fontconfig",
            pkgConfig: "fontconfig",
            providers: [.apt(["libfontconfig1-dev"])]
        ),
    ]
)
