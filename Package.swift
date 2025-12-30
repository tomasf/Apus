// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Apus",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Apus", targets: ["Apus"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tomasf/freetype-spm.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "harfbuzz",
            dependencies: [
                .product(name: "freetype", package: "freetype-spm"),
            ],
            path: "Sources/harfbuzz",
            sources: ["src/harfbuzz.cc"],
            publicHeadersPath: "src",
            cxxSettings: [
                .define("HAVE_FREETYPE"),
            ]
        ),
        .target(
            name: "Apus",
            dependencies: [
                "harfbuzz",
                .product(name: "freetype", package: "freetype-spm"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .testTarget(
            name: "ApusTests",
            dependencies: ["Apus"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
